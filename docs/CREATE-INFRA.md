# Create MongoDB infrastructure

This guide covers how to create the MongoDB-on-EC2 stack using Terraform, either via the **create-mongo-infra** script or **manually**. It includes examples for dev, staging, and prod, and troubleshooting.

---

## Table of contents

- [Overview](#overview)
- [What gets created](#what-gets-created)
- [Prerequisites](#prerequisites)
- [Option A: Script (recommended)](#option-a-script-recommended)
- [Option B: Manual Terraform](#option-b-manual-terraform)
- [Apply-only script (code changes)](#apply-only-script-code-changes)
- [Environment and naming](#environment-and-naming)
- [Examples](#examples)
- [After apply](#after-apply)
- [Troubleshooting](#troubleshooting)

---

## Overview

The setup provisions:

- **EC2** instance (Amazon Linux 2023) with MongoDB 8.2 installed at boot via user-data
- **EBS** volume for MongoDB data (persists across instance replacement)
- **Elastic IP** for a stable connection host
- **SSM Parameter Store** parameters for root username and password (per environment)
- **Security groups**, IAM roles, SSH key pair, and optional ECS/EFS resources

You can run **multiple environments** (dev, staging, prod) in the same AWS account; each uses a different name prefix and SSM path.

---

## What gets created

| Environment (`terraform.tfvars`) | Name prefix | SSM path    | Example key file        | Outputs file              |
|----------------------------------|-------------|-------------|--------------------------|----------------------------|
| `dev`                             | `dev_`      | `/mongodb/dev`   | `dev_mongo-key.pem`      | `outputs/dev_outputs.json` |
| `staging`                         | `stage_`    | `/mongodb/stage` | `stage_mongo-key.pem`    | `outputs/stage_outputs.json` |
| `prod`                            | `prod_`     | `/mongodb/prod`  | `prod_mongo-key.pem`     | `outputs/prod_outputs.json` |

Terraform also writes `outputs/<env_prefix>_outputs.json` with `ec2_public_ip`, `ssh_private_key_path`, `mongodb_connection_string`, and `environment`.

---

## Prerequisites

- **Terraform** >= 1.14.5 ([install](https://www.terraform.io/downloads))
- **AWS CLI** configured (credentials or SSO)
- **AWS account** with a default VPC in the chosen region (or adapt `main.tf` for a custom VPC)
- **Permissions**: see [docs/IAM-MINIMAL-POLICIES.md](IAM-MINIMAL-POLICIES.md) (PowerUserAccess + IAMFullAccess typical)

Ensure your shell can run the script:

```bash
# Mac/Linux: make script executable once
chmod +x scripts/create-mongo-infra.sh
```

---

## Option A: Script (recommended)

The script runs from the **project root**. It either uses an existing `terraform.tfvars` or generates one from environment variables, then runs `terraform init -reconfigure` and `terraform apply`.

### When `terraform.tfvars` exists

The script runs Terraform with that file. No env vars required.

```bash
# From project root
./scripts/create-mongo-infra.sh
```

You will be prompted to confirm `terraform apply` unless `AUTO_APPROVE` is set.

### When `terraform.tfvars` does not exist

The script **generates** `terraform.tfvars` from environment variables and then runs Terraform. Required:

- `AWS_ACCOUNT_ID` — 12-digit AWS account ID
- `MONGO_PASSWORD` — MongoDB root password (stored in SSM)
- `MONGO_ENVIRONMENT` — `dev`, `staging`, or `prod`

Optional:

- `MONGO_USERNAME` (default: `mongolabadmin`)
- `MONGO_DB_NAME` (default: `mongolab`)
- `AWS_REGION` (default: `eu-central-1`)
- `AUTO_APPROVE` — set to `1` or `true` to skip apply confirmation

**Examples (Mac/Linux/Git Bash):**

```bash
# Dev, interactive apply
AWS_ACCOUNT_ID=123456789012 MONGO_PASSWORD='YourSecure1!' MONGO_ENVIRONMENT=dev ./scripts/create-mongo-infra.sh

# Staging, non-interactive (CI-friendly)
export AWS_ACCOUNT_ID=123456789012
export MONGO_PASSWORD='StagingPass1!'
export MONGO_ENVIRONMENT=staging
export AUTO_APPROVE=1
./scripts/create-mongo-infra.sh

# Prod with custom region
AWS_ACCOUNT_ID=123456789012 MONGO_PASSWORD='ProdPass1!' MONGO_ENVIRONMENT=prod AWS_REGION=eu-west-1 ./scripts/create-mongo-infra.sh
```

**Windows (PowerShell):**

```powershell
$env:AWS_ACCOUNT_ID = "123456789012"
$env:MONGO_PASSWORD = "YourSecure1!"
$env:MONGO_ENVIRONMENT = "dev"
.\scripts\create-mongo-infra.ps1
```

---

## Option B: Manual Terraform

1. **Create tfvars** from an example and edit:

   ```bash
   # Pick one per environment
   cp terraform.tfvars.example.dev     terraform.tfvars   # dev
   cp terraform.tfvars.example.staging terraform.tfvars   # staging
   cp terraform.tfvars.example.prod    terraform.tfvars   # prod
   ```

2. **Edit** `terraform.tfvars`: set `aws_account_id`, `mongodb_root_password`, and for production tighten `ssh_allowed_cidrs` and `mongodb_allowed_cidrs`.

3. **Init and apply:**

   ```bash
   terraform init -reconfigure
   terraform apply
   ```

---

## Apply-only script (code changes)

When you **only change Terraform code** (e.g. `main.tf`, `variables.tf`, or tfvars) and want to apply **without** creating a new instance or touching the password, use the apply-only script. It requires an existing `terraform.tfvars` and runs `terraform init -reconfigure` and `terraform apply`.

**Shell (Mac/Linux/Git Bash):**

```bash
./scripts/apply-mongo-infra.sh
# Or non-interactive:
AUTO_APPROVE=1 ./scripts/apply-mongo-infra.sh
```

**PowerShell (Windows):**

```powershell
.\scripts\apply-mongo-infra.ps1
# Or: .\scripts\apply-mongo-infra.ps1 -AutoApprove
```

Use **create-mongo-infra** for the first run or when you want to (re)generate tfvars from env vars. Use **apply-mongo-infra** for routine applies after code changes. Full guide: [APPLY-INFRA.md](APPLY-INFRA.md).

---

## Environment and naming

| `environment` in tfvars | Resource prefix | SSM path      |
|-------------------------|----------------|---------------|
| `dev`                    | `dev_`         | `/mongodb/dev`   |
| `staging`                | `stage_`       | `/mongodb/stage` |
| `prod`                   | `prod_`        | `/mongodb/prod`  |

- **Resources** (e.g. security groups, key pair, IAM) get the prefix so dev/staging/prod can coexist.
- **SSM** parameters live under the path above (e.g. `/mongodb/dev/MONGO_INITDB_ROOT_PASSWORD`).
- **SSH key** and **outputs JSON** are named with the same prefix (e.g. `dev_mongo-key.pem`, `outputs/dev_outputs.json`).

---

## Examples

### Example 1: First-time dev from env vars

```bash
cd /path/to/MongoTF
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
MONGO_PASSWORD='ChangeMe123!' MONGO_ENVIRONMENT=dev ./scripts/create-mongo-infra.sh
# Confirm with 'yes' when Terraform asks
```

### Example 2: Staging from existing tfvars

```bash
cp terraform.tfvars.example.staging terraform.tfvars
# Edit: aws_account_id, mongodb_root_password, and CIDRs
./scripts/create-mongo-infra.sh
```

### Example 3: Prod with auto-approve (e.g. CI)

```bash
export AWS_ACCOUNT_ID=123456789012
export MONGO_PASSWORD="$MONGO_PROD_PASSWORD_FROM_VAULT"
export MONGO_ENVIRONMENT=prod
export AUTO_APPROVE=1
./scripts/create-mongo-infra.sh
```

### Example 4: Manual apply with plan first

```bash
cp terraform.tfvars.example.prod terraform.tfvars
# Edit tfvars
terraform init -reconfigure
terraform plan -out=tfplan
terraform apply tfplan
```

---

## After apply

- **Connection:** Use `ec2_public_ip` and `mongodb_connection_string` from `terraform output` or `outputs/<env>_outputs.json`. Replace `<PASSWORD>` with the password (from tfvars or SSM).
- **SSH:** Use `ssh_private_key_path` from the same outputs and the same IP.
- **Rotate password later:** Use the [rotate-password script](ROTATE-PASSWORD.md).

---

## Troubleshooting

| Issue | Cause | What to do |
|-------|--------|------------|
| **`terraform.tfvars not found`** | No tfvars and env vars not set (or missing one of `AWS_ACCOUNT_ID`, `MONGO_PASSWORD`, `MONGO_ENVIRONMENT`). | Create tfvars from an example, or set all required env vars and run the script again. |
| **`terraform not found`** | Terraform not installed or not on PATH. | Install Terraform and ensure it’s on PATH (e.g. `terraform version`). |
| **`aws_account_id must be exactly 12 digits`** | Invalid or missing `aws_account_id` in tfvars. | Set `aws_account_id` to your 12-digit account ID (`aws sts get-caller-identity --query Account --output text`). |
| **AWS account ID mismatch** | tfvars `aws_account_id` does not match the account of your current AWS credentials. | Fix `aws_account_id` in tfvars or use the correct profile/credentials. |
| **ExpiredToken / 403 from AWS** | AWS credentials expired (e.g. SSO). | Refresh: `aws sso login` or re-export access keys / `AWS_PROFILE`. |
| **Error: NoSuchBucket (S3 backend)** | Backend still points at S3 but the bucket was deleted or never created. | Default backend is local; run `terraform init -reconfigure` so Terraform uses local state. If you need S3, create the bucket and use a backend config (see README). |
| **Backend "dynamodb_table is deprecated"** | An old backend config uses `dynamodb_table`. | Use S3-native locking: in backend config set `use_lockfile = true` and remove `dynamodb_table` (see `backend.hcl.example`). |
| **Permission denied: ./scripts/create-mongo-infra.sh** | Script not executable. | Run `chmod +x scripts/create-mongo-infra.sh` once. |
| **State lock / init fails** | Stale local state or wrong backend. | Run `terraform init -reconfigure` from the project root. |

For more on IAM and permissions, see [IAM-MINIMAL-POLICIES.md](IAM-MINIMAL-POLICIES.md).
