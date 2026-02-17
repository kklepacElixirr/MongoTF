# AWS Backup for MongoDB EC2 instance and attached EBS volumes.
# Deploy after the main MongoTF stack; pass ec2_instance_id (and optional ebs_volume_id) from its outputs.

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
  required_version = ">= 1.5.0"
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# IAM role for AWS Backup (create snapshots, manage recovery points)
resource "aws_iam_role" "backup" {
  name               = "${var.backup_plan_name}-role"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "backup.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "backup" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
  role       = aws_iam_role.backup.name
}

# Backup vault (encrypted container for recovery points)
resource "aws_backup_vault" "mongodb" {
  name        = var.backup_vault_name
  kms_key_arn = var.backup_vault_kms_key_arn
  tags        = var.tags
}

# Backup plan: schedule and retention
resource "aws_backup_plan" "mongodb" {
  name = var.backup_plan_name

  rule {
    rule_name                = "daily-mongodb"
    target_vault_name        = aws_backup_vault.mongodb.name
    schedule                 = var.schedule_cron
    start_window_minutes     = 60
    completion_window_minutes = 120

    lifecycle {
      delete_after = var.retention_days
    }
  }

  tags = var.tags
}

# Build list of resource ARNs: EC2 instance (includes attached EBS in backup) and optionally explicit EBS volume(s)
locals {
  instance_arn = "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/${var.ec2_instance_id}"
  volume_arns = [for id in var.ebs_volume_ids : "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:volume/${id}"]
  resources   = distinct(concat([local.instance_arn], local.volume_arns))
}

# Assign the MongoDB instance (and optional EBS volumes) to the plan
resource "aws_backup_selection" "mongodb" {
  name         = "${var.backup_plan_name}-selection"
  plan_id      = aws_backup_plan.mongodb.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = local.resources
}
