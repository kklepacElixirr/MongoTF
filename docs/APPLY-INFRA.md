# Apply Terraform changes only

This guide covers the **apply-mongo-infra** script: when to use it, how to run it, and how it differs from the create and rotate-password scripts. Use it when you changed Terraform code and want to apply without creating a new instance or changing the MongoDB password.

---

## Table of contents

- [Overview](#overview)
- [When to use which script](#when-to-use-which-script)
- [Prerequisites](#prerequisites)
- [Usage](#usage)
- [Examples](#examples)
- [What the script does](#what-the-script-does)
- [Troubleshooting](#troubleshooting)

---

## Overview

The **apply-mongo-infra** script runs only:

1. **`terraform init -reconfigure`** — (Re)initialize the backend and providers.
2. **`terraform apply`** — Apply the current Terraform configuration.

It does **not**:

- Generate or modify `terraform.tfvars` (you must already have it).
- Create a new instance from scratch (use [create-mongo-infra](CREATE-INFRA.md) for that).
- Change the MongoDB password or SSM (use [rotate-mongo-password](ROTATE-PASSWORD.md) for that).

Typical use: you edited `main.tf`, `variables.tf`, or `terraform.tfvars` (e.g. instance type, volume size, CIDRs) and want to apply those changes to the existing stack.

---

## When to use which script

| Script | Use when |
|--------|----------|
| **create-mongo-infra** | First-time setup, or you want to generate `terraform.tfvars` from env vars and then apply. |
| **apply-mongo-infra** | You already have `terraform.tfvars` and only changed Terraform code; apply changes without creating a new instance or touching the password. |
| **rotate-mongo-password** | You only need to change the MongoDB root password and keep SSM in sync with the running instance. |

---

## Prerequisites

- **terraform.tfvars** must exist in the project root (from a previous create or copied from an example).
- **Terraform** installed and on PATH ([install](https://www.terraform.io/downloads)).
- **AWS credentials** configured (same as for any Terraform run; see [IAM-MINIMAL-POLICIES.md](IAM-MINIMAL-POLICIES.md)).

Make the script executable once (Mac/Linux):

```bash
chmod +x scripts/apply-mongo-infra.sh
```

---

## Usage

### Shell (Mac / Linux / Git Bash on Windows)

```bash
./scripts/apply-mongo-infra.sh
```

You will be prompted to confirm `terraform apply` unless you skip the prompt:

```bash
# Non-interactive (e.g. CI)
AUTO_APPROVE=1 ./scripts/apply-mongo-infra.sh
```

### PowerShell (Windows)

```powershell
.\scripts\apply-mongo-infra.ps1
```

Skip the apply confirmation:

```powershell
.\scripts\apply-mongo-infra.ps1 -AutoApprove
# Or: $env:AUTO_APPROVE = "1"; .\scripts\apply-mongo-infra.ps1
```

---

## Examples

### Example 1: Apply after changing instance type in tfvars

You edited `terraform.tfvars` and set `ec2_instance_type = "t3.small"`. From the project root:

```bash
./scripts/apply-mongo-infra.sh
# Review the plan, type yes to apply
```

### Example 2: Apply after editing main.tf (e.g. security group rules)

```bash
./scripts/apply-mongo-infra.sh
```

### Example 3: Apply without prompt (CI or scripted run)

```bash
AUTO_APPROVE=1 ./scripts/apply-mongo-infra.sh
```

### Example 4: Windows PowerShell

```powershell
cd C:\path\to\MongoTF
.\scripts\apply-mongo-infra.ps1 -AutoApprove
```

---

## What the script does

1. **Checks** that `terraform.tfvars` exists in the project root; exits with an error if not.
2. **Checks** that `terraform` is on PATH; exits if not.
3. **Changes directory** to the project root.
4. **Runs** `terraform init -reconfigure` (so the backend and providers match the config).
5. **Runs** `terraform apply` (or `terraform apply -auto-approve` if `AUTO_APPROVE` is set).

After a successful apply, Terraform updates state and may update the `outputs/<env>_outputs.json` file (e.g. if the IP or key path changed). Use that file or `terraform output` for connection details.

---

## Troubleshooting

| Issue | Cause | What to do |
|-------|--------|------------|
| **`terraform.tfvars not found`** | No tfvars file in the project root. | Create it from an example (e.g. `cp terraform.tfvars.example.dev terraform.tfvars` and edit), or run [create-mongo-infra](CREATE-INFRA.md) first so tfvars exists. |
| **`terraform not found`** | Terraform not installed or not on PATH. | Install Terraform and ensure it’s on PATH (`terraform version`). |
| **ExpiredToken / 403 from AWS** | AWS credentials expired. | Refresh credentials (e.g. `aws sso login` or re-export keys / `AWS_PROFILE`). |
| **Account ID mismatch** | `aws_account_id` in tfvars doesn’t match current credentials. | Fix `aws_account_id` in tfvars or use the correct AWS profile. |
| **Permission denied: ./scripts/apply-mongo-infra.sh** | Script not executable. | Run `chmod +x scripts/apply-mongo-infra.sh` once. |
| **State lock / init fails** | Stale backend or state. | Run `terraform init -reconfigure` manually from the project root; fix any backend config (e.g. missing S3 bucket) or use local backend. |

For more on creating the stack or rotating the password, see [CREATE-INFRA.md](CREATE-INFRA.md) and [ROTATE-PASSWORD.md](ROTATE-PASSWORD.md).
