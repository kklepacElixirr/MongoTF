# AWS Backup for MongoDB (MongoTF)

This directory contains a **separate Terraform root module** that configures [AWS Backup](https://docs.aws.amazon.com/aws-backup/) for the MongoDB EC2 instance and its EBS volume(s) created by the main MongoTF stack.

## What it creates

- **Backup vault** – Encrypted container for recovery points.
- **Backup plan** – Daily schedule (configurable cron) and retention.
- **Backup selection** – Assigns your EC2 instance (and optionally specific EBS volumes) to the plan.
- **IAM role** – Used by AWS Backup to create and manage snapshots.

Backing up the **EC2 instance** includes all attached EBS volumes (root + data volume). You can optionally add more EBS volume IDs via `ebs_volume_ids` if needed.

## Prerequisites

1. The main MongoTF stack must be applied so the EC2 instance (and EBS volume) exist.
2. You need the **EC2 instance ID** (and optionally the **EBS volume ID**) from the main stack.

## Getting IDs from the main stack

From the **repository root** (where the main Terraform lives):

```bash
terraform output -raw ec2_instance_id
terraform output -raw ebs_volume_id
```

Or read from the outputs file, e.g. `outputs/dev_outputs.json`:

```bash
jq -r '.ec2_instance_id' ../outputs/dev_outputs.json
jq -r '.ebs_volume_id' ../outputs/dev_outputs.json
```

## Usage

1. Copy the example tfvars and set at least `aws_region` and `ec2_instance_id`:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars and set ec2_instance_id (and optionally ebs_volume_ids)
   ```

2. Initialize and apply from this directory:

   ```bash
   cd backup
   terraform init
   terraform plan
   terraform apply
   ```

3. (Optional) Use the same AWS region as the main stack. State is stored locally by default; use a `backend` block and `backend.hcl` if you want remote state for the backup module.

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region (same as main stack) | (required) |
| `ec2_instance_id` | EC2 instance ID from main stack | (required) |
| `ebs_volume_ids` | Optional list of EBS volume IDs | `[]` |
| `backup_vault_name` | Backup vault name | `mongolab-backup-vault` |
| `backup_plan_name` | Backup plan name | `mongolab-daily-backup` |
| `schedule_cron` | Cron for backup (UTC) | `cron(0 5 * * ? *)` (daily 05:00 UTC) |
| `retention_days` | Retention in days | `14` |

## Restore

Use the **AWS Backup** console (or CLI) in the same region to restore a recovery point to a new EC2 instance or to restore EBS volumes. The backup plan creates recovery points for the instance and its attached volumes.
