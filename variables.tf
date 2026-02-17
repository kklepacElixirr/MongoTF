variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "mongodb_root_username" {
  description = "MongoDB root username"
  type        = string
  default     = "mongolabadmin"
}

variable "mongodb_root_password" {
  description = "MongoDB root password (initial value for SSM - change via AWS Console after first apply)"
  type        = string
  default     = "Dummy"
  sensitive   = true
}

variable "mongodb_database" {
  description = "MongoDB database name"
  type        = string
  default     = "mongolab"
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "mongodb_allowed_cidrs" {
  description = "CIDR blocks allowed for MongoDB access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ec2_instance_type" {
  description = "EC2 instance type for MongoDB"
  type        = string
  default     = "t2.micro"
}

variable "ec2_ami" {
  description = "AMI ID for EC2 (empty = use latest Amazon Linux 2023)"
  type        = string
  default     = ""
}

variable "key_pair_name" {
  description = "Name of the SSH key pair"
  type        = string
  default     = "mongolabkey"
}

variable "mongo_image" {
  description = "Docker image for ECS MongoDB task"
  type        = string
  default     = "mongo:latest"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "ecs_task_cpu" {
  description = "ECS task CPU units"
  type        = string
  default     = "256"
}

variable "ecs_task_memory" {
  description = "ECS task memory in MB"
  type        = string
  default     = "512"
}

variable "ec2_health_alarm_sns_topic_arn" {
  description = "Optional SNS topic ARN for EC2 health alarm notifications"
  type        = string
  default     = null
}

variable "ec2_mongodb_volume_size" {
  description = "EBS volume size in GB for MongoDB data (persists across instance replacement)"
  type        = number
  default     = 20
}
