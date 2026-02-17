variable "aws_region" {
  description = "AWS region (must match the region where the MongoDB EC2 instance lives)"
  type        = string
}

variable "ec2_instance_id" {
  description = "EC2 instance ID to back up (from main Terraform: ec2_instance_id output). Backing up the instance includes its attached EBS volumes."
  type        = string
}

variable "ebs_volume_ids" {
  description = "Optional list of EBS volume IDs to include explicitly (e.g. data volume). Instance backup already includes attached volumes; use this if you want to add standalone volumes."
  type        = list(string)
  default     = []
}

variable "backup_vault_name" {
  description = "Name of the backup vault"
  type        = string
  default     = "mongolab-backup-vault"
}

variable "backup_vault_kms_key_arn" {
  description = "KMS key ARN for the backup vault (optional; default AWS key used if null)"
  type        = string
  default     = null
}

variable "backup_plan_name" {
  description = "Name of the backup plan"
  type        = string
  default     = "mongolab-daily-backup"
}

variable "schedule_cron" {
  description = "Cron expression for backup schedule (UTC). Default: daily at 05:00 UTC."
  type        = string
  default     = "cron(0 5 * * ? *)"
}

variable "retention_days" {
  description = "Number of days to retain recovery points"
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags to apply to backup vault and plan"
  type        = map(string)
  default     = {}
}
