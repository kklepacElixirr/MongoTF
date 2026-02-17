terraform {

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.40.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.5"
    }
  }

  required_version = ">= 1.14.5"
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {}

# Default VPC
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Latest Amazon Linux 2023 AMI (required for MongoDB 8.2 repo)
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Parameter store

resource "aws_ssm_parameter" "mongodb_secret_password" {
  name  = "/mongodb/MONGO_INITDB_ROOT_PASSWORD"
  type  = "SecureString"
  value = var.mongodb_root_password

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "mongodb_root_username" {
  name  = "/mongodb/MONGO_INITDB_ROOT_USERNAME"
  type  = "String"
  value = var.mongodb_root_username
}

resource "aws_iam_policy" "ssm_parameter_access" {
  name        = "ssm_parameter_access"
  description = "Allow ECS tasks to access SSM parameters"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameters",
          "ssm:GetParameter",
          "ssm:DescribeParameters",
          "kms:Decrypt"
        ]
        Resource = aws_ssm_parameter.mongodb_secret_password.arn
      }
    ]
  })
}

# EC2 instance profile - SSM access for MongoDB auth setup
resource "aws_iam_role" "ec2_mongo_role" {
  name = "ec2-mongo-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_ssm_access" {
  name   = "ec2-ssm-mongodb"
  role   = aws_iam_role.ec2_mongo_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          aws_ssm_parameter.mongodb_secret_password.arn,
          aws_ssm_parameter.mongodb_root_username.arn
        ]
      },
      {
        Effect = "Allow"
        Action = "kms:Decrypt"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_mongo" {
  name = "ec2-mongo-profile"
  role = aws_iam_role.ec2_mongo_role.name
}

# After the code for AWS SSM Paramter Store parameter has been added we must apply the changes to the infrastructure so we are able to change the password.
# If you are using the example code to deploy the infrastructure, you should comment out everything below here before running terraform init and apply.

resource "aws_iam_role" "ecs_mongo_task_execution_role" {
  name = "ecs_mongo_task_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_mongo_task_execution_role_policy" {
  role       = aws_iam_role.ecs_mongo_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs_ssm_parameter_access" {
  role       = aws_iam_role.ecs_mongo_task_execution_role.name
  policy_arn = aws_iam_policy.ssm_parameter_access.arn
}

resource "aws_iam_role" "ecs_mongo_task_role" {
  name = "ecs_mongo_task_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      },
    ]
  })
}

resource "aws_security_group" "ec2_sg" {
  name        = "ec2_sg"
  description = "Security group for EC2 instance"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = var.mongodb_allowed_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "mongo_ecs_tasks_sg" {
  name        = "mongo-ecs-tasks-sg"
  description = "Security group for ECS MongoDB tasks"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mongolab-ecs-tasks-sg"
  }
}

resource "aws_security_group" "efs_sg" {
  name        = "efs-mongolab-sg"
  description = "Security group for EFS"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }
}

resource "aws_efs_file_system" "mongolab_file_system" {
  creation_token = "mongoefs"
  encrypted      = true

  tags = {
    Name = "mongoefs"
  }
}

resource "aws_efs_mount_target" "efs_mount_target" {
  count           = length(data.aws_subnets.default.ids)
  file_system_id  = aws_efs_file_system.mongolab_file_system.id
  subnet_id       = tolist(data.aws_subnets.default.ids)[count.index]
  security_groups = [aws_security_group.efs_sg.id]
}


resource "aws_iam_policy" "ecs_efs_access_policy" {
  name        = "ecs_efs_access_policy"
  description = "Allow ECS tasks to access EFS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets"
        ]
        Resource = aws_efs_file_system.mongolab_file_system.arn
        Effect   = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_efs_access_policy_attachment" {
  role       = aws_iam_role.ecs_mongo_task_role.name
  policy_arn = aws_iam_policy.ecs_efs_access_policy.arn
}


resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/mongolab-${var.environment}"
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_cluster" "mongolab_cluster" {
  name = "mongolab-cluster"
}

resource "aws_ecs_task_definition" "mongo_task_definition" {
  family                   = "mongolab-mongodb-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_mongo_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_mongo_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "mongo",
      image     = var.mongo_image,
      cpu       = 256,
      memory    = 512,
      essential = true,
      portMappings = [
        {
          protocol      = "tcp"
          containerPort = 27017
          hostPort      = 27017
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "mongoEfsVolume"
          containerPath = "/data/db"
          readOnly      = false
        },
      ],
      environment = [
        {
          name  = "MONGO_INITDB_ROOT_USERNAME"
          value = var.mongodb_root_username
        },
        {
          name  = "MONGO_INITDB_DATABASE"
          value = var.mongodb_database
        }
      ],
      secrets = [
        {
          name      = "MONGO_INITDB_ROOT_PASSWORD"
          valueFrom = aws_ssm_parameter.mongodb_secret_password.name
        }
      ],
      healthcheck = {
        command     = ["CMD-SHELL", "echo 'db.runCommand(\\\"ping\\\").ok' | mongosh mongodb://localhost:27017/test"]
        interval    = 30
        timeout     = 15
        retries     = 3
        startPeriod = 15
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_logs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "mongodb"
        }
      }
    }
  ])

  volume {
    name = "mongoEfsVolume"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.mongolab_file_system.id
      transit_encryption = "ENABLED"
      authorization_config {
        iam = "ENABLED"
      }
    }
  }
}

resource "aws_service_discovery_private_dns_namespace" "mongolab_monitoring" {
  name = "mongolab.local"
  vpc  = data.aws_vpc.default.id
}

resource "aws_service_discovery_service" "mongo_discovery_service" {
  name = "mongodb"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.mongolab_monitoring.id

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_ecs_service" "mongo_service" {
  name            = "mongolab-mongodb-service"
  cluster         = aws_ecs_cluster.mongolab_cluster.id
  task_definition = aws_ecs_task_definition.mongo_task_definition.id
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.mongo_ecs_tasks_sg.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.mongo_discovery_service.arn
  }

}

# EC2 instance - SSH key (generated by Terraform if you don't have one)

resource "tls_private_key" "mongo" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ec2_keypair" {
  key_name   = var.key_pair_name
  public_key = tls_private_key.mongo.public_key_openssh
}

resource "local_file" "mongo_private_key" {
  content         = tls_private_key.mongo.private_key_pem
  filename        = "${path.module}/mongo-key.pem"
  file_permission = "0600"
}

resource "aws_eip" "mongo" {
  domain = "vpc"
  tags = {
    Name = "mongolab-eip-${var.environment}"
  }
}

# EBS volume for MongoDB data (MongoDB WiredTiger does not support EFS/NFS)
data "aws_subnet" "ec2_subnet" {
  id = tolist(data.aws_subnets.default.ids)[0]
}
resource "aws_ebs_volume" "mongodb_data" {
  availability_zone = data.aws_subnet.ec2_subnet.availability_zone
  size              = var.ec2_mongodb_volume_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "mongolab-mongodb-data-${var.environment}"
  }
}

resource "aws_instance" "mongolab_ec2_instance" {
  ami                  = var.ec2_ami != "" ? var.ec2_ami : data.aws_ami.amazon_linux_2023.id
  instance_type        = var.ec2_instance_type
  subnet_id            = tolist(data.aws_subnets.default.ids)[0]
  key_name             = aws_key_pair.ec2_keypair.key_name
  iam_instance_profile = aws_iam_instance_profile.ec2_mongo.name

  security_groups = [aws_security_group.ec2_sg.id]

  user_data = templatefile("${path.module}/user-data.sh", {
    aws_region = var.aws_region
  })

  tags = {
    Name        = "mongolab-mongodb-${var.environment}"
    Role        = "mongodb"
    Environment = var.environment
  }
}

resource "aws_volume_attachment" "mongodb_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.mongodb_data.id
  instance_id = aws_instance.mongolab_ec2_instance.id
}

resource "aws_eip_association" "mongo" {
  instance_id   = aws_instance.mongolab_ec2_instance.id
  allocation_id = aws_eip.mongo.id
}

# EC2 health check: CloudWatch alarm on status check failures (system + instance reachability)
resource "aws_cloudwatch_metric_alarm" "mongodb_ec2_health" {
  alarm_name          = "mongolab-ec2-health-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0

  dimensions = {
    InstanceId = aws_instance.mongolab_ec2_instance.id
  }

  alarm_description = "MongoDB EC2 instance status check failed (system or instance unreachable)"
  alarm_actions      = var.ec2_health_alarm_sns_topic_arn != null ? [var.ec2_health_alarm_sns_topic_arn] : []
  treat_missing_data = "breaching"
}

output "ssh_private_key_path" {
  description = "Path to the generated SSH private key for EC2 access"
  value       = local_file.mongo_private_key.filename
}

output "ec2_public_ip" {
  description = "Static public IP of the MongoDB EC2 instance (Elastic IP)"
  value       = aws_eip.mongo.public_ip
}

output "ec2_ami_used" {
  description = "AMI ID used for the EC2 instance"
  value       = aws_instance.mongolab_ec2_instance.ami
}

output "mongodb_connection_string" {
  description = "MongoDB connection string (with auth)"
  value       = "mongodb://${var.mongodb_root_username}:<PASSWORD>@${aws_eip.mongo.public_ip}:27017"
}


