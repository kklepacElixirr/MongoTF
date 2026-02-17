provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  name       = var.project_name
}

# S3 bucket for Terraform state
resource "aws_s3_bucket" "terraform_state" {
  bucket = "${local.name}-terraform-state-${local.account_id}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# DynamoDB for state locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${local.name}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# IAM role for CodeBuild
resource "aws_iam_role" "codebuild" {
  name = "${local.name}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  name   = "${local.name}-codebuild-policy"
  role   = aws_iam_role.codebuild.id
  policy = data.aws_iam_policy_document.codebuild.json
}

data "aws_iam_policy_document" "codebuild" {
  statement {
    sid    = "S3State"
    effect = "Allow"
    actions = [
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*"
    ]
  }

  statement {
    sid    = "DynamoDBLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem",
      "dynamodb:ConditionCheckItem", "dynamodb:BatchGetItem"
    ]
    resources = [aws_dynamodb_table.terraform_locks.arn]
  }

  statement {
    sid    = "CodeCommit"
    effect = "Allow"
    actions = [
      "codecommit:GitPull"
    ]
    resources = ["arn:aws:codecommit:${local.region}:${local.account_id}:${var.codecommit_repository_name}"]
  }

  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"
    ]
    resources = ["*"]
  }

  # Terraform needs broad permissions to create MongoDB infra (EC2, ECS, IAM, SSM, etc.)
  statement {
    sid    = "TerraformResources"
    effect = "Allow"
    actions = ["*"]
    resources = ["*"]
  }
}

# CodeBuild project
resource "aws_codebuild_project" "terraform" {
  name          = "${local.name}-terraform"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 60

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type            = "LINUX_CONTAINER"
    image           = "public.ecr.aws/hashicorp/terraform:1.5"
    compute_type    = "BUILD_GENERAL1_SMALL"
    privileged_mode = false

    environment_variable {
      name  = "TF_STATE_BUCKET"
      value = aws_s3_bucket.terraform_state.bucket
    }
    environment_variable {
      name  = "TF_STATE_KEY"
      value = "${local.name}/terraform.tfstate"
    }
    environment_variable {
      name  = "TF_STATE_LOCK_TABLE"
      value = aws_dynamodb_table.terraform_locks.name
    }
    environment_variable {
      name  = "APPROVE_APPLY"
      value = var.approve_apply ? "true" : "false"
    }
    environment_variable {
      name  = "TF_VAR_aws_account_id"
      value = local.account_id
    }
    environment_variable {
      name  = "TF_VAR_aws_region"
      value = local.region
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }
}

# CodePipeline
resource "aws_iam_role" "codepipeline" {
  name = "${local.name}-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "codepipeline" {
  name   = "${local.name}-codepipeline-policy"
  role   = aws_iam_role.codepipeline.id
  policy = data.aws_iam_policy_document.codepipeline.json
}

data "aws_iam_policy_document" "codepipeline" {
  statement {
    sid    = "CodeCommit"
    effect = "Allow"
    actions = [
      "codecommit:GetBranch", "codecommit:GetCommit", "codecommit:GetRepository",
      "codecommit:ListBranches", "codecommit:ListRepositories"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "CodeBuild"
    effect = "Allow"
    actions = [
      "codebuild:BatchGetBuilds", "codebuild:StartBuild"
    ]
    resources = [aws_codebuild_project.terraform.arn]
  }

  statement {
    sid    = "Artifacts"
    effect = "Allow"
    actions = [
      "s3:GetObject", "s3:PutObject"
    ]
    resources = [
      "${aws_s3_bucket.pipeline_artifacts.arn}/*"
    ]
  }
}

resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket = "${local.name}-pipeline-artifacts-${local.account_id}"
}

resource "aws_s3_bucket_versioning" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_codepipeline" "terraform" {
  name     = "${local.name}-terraform-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["source"]

      configuration = {
        RepositoryName       = var.codecommit_repository_name
        BranchName           = "main"
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Terraform"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source"]
      output_artifacts = ["terraform-plan"]

      configuration = {
        ProjectName = aws_codebuild_project.terraform.name
      }
    }
  }
}
