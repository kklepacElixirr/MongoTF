# Terraform CI/CD with CodePipeline

Automated Terraform **plan** and optional **apply** via AWS CodePipeline and CodeBuild. The pipeline is triggered on push to the configured CodeCommit branch (e.g. `main`).

---

## Table of contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Step 1: Bootstrap the CI/CD stack](#step-1-bootstrap-the-cicd-stack)
- [Step 2: Migrate main project to S3 backend](#step-2-migrate-main-project-to-s3-backend)
- [Step 3: Configure auto-apply (optional)](#step-3-configure-auto-apply-optional)
- [Step 4: Set Terraform variables for CodeBuild](#step-4-set-terraform-variables-for-codebuild)
- [Step 5: Trigger the pipeline](#step-5-trigger-the-pipeline)
- [Branches and manual apply](#branches-and-manual-apply)
- [File layout](#file-layout)
- [Troubleshooting](#troubleshooting)

---

## Overview

1. **Bootstrap (run once):** The `cicd` Terraform creates the S3 state bucket, DynamoDB lock table, CodePipeline, and CodeBuild project.
2. **Main project:** Uses the S3 backend; every pipeline run runs `terraform init`, `terraform plan`, and optionally `terraform apply` from the root using `buildspec.yml`.

Pipeline flow: **Source (CodeCommit)** → **Build (CodeBuild:** init → validate → plan → apply if enabled).

---

## Prerequisites

- A **CodeCommit** repository named `MongoTF` (or match your repo name). See [CODECOMMIT.md](CODECOMMIT.md) for creating the repo and pushing code.
- **CICD repo name:** The `cicd` module’s `codecommit_repository_name` must match the CodeCommit repo name exactly (case-sensitive). For this project use `codecommit_repository_name = "MongoTF"` in `cicd/terraform.tfvars`.

---

## Step 1: Bootstrap the CI/CD stack

**First run:** The `cicd` module uses an S3 backend, but the bucket is created by this same apply. So for the first run only, use local state:

1. In `cicd/backend.tf`, **comment out** the `backend "s3" { ... }` block (leave the rest of the file).
2. From the project root:

```bash
cd cicd
terraform init
terraform apply
```

3. **Migrate cicd state to S3** so the pipeline can later auto-apply cicd (optional but recommended). Uncomment the `backend "s3"` block in `cicd/backend.tf`, then:

```bash
cd cicd
terraform init -migrate-state -reconfigure \
  -backend-config="bucket=$(terraform output -raw terraform_state_bucket)" \
  -backend-config="key=cicd/terraform.tfstate" \
  -backend-config="dynamodb_table=$(terraform output -raw terraform_lock_table)" \
  -backend-config="region=eu-central-1"
```

(Replace `eu-central-1` with your region.)

This creates:

- **S3 bucket** for Terraform state
- **DynamoDB table** for state locking
- **CodePipeline** (source: CodeCommit, build: CodeBuild)
- **CodeBuild project** that runs `buildspec.yml` in the project root

Note the outputs for the next step.

---

## Step 2: Migrate main project to S3 backend

After bootstrap, point the **main** Terraform at the S3 backend. From the **project root** (not `cicd`):

**Option A — Using outputs (recommended)**

Replace `eu-central-1` with your region if different:

```bash
cd ..   # project root
terraform init -reconfigure \
  -backend-config="bucket=$(cd cicd && terraform output -raw terraform_state_bucket)" \
  -backend-config="key=$(cd cicd && terraform output -raw terraform_state_key)" \
  -backend-config="dynamodb_table=$(cd cicd && terraform output -raw terraform_lock_table)" \
  -backend-config="region=eu-central-1"
```

**Option B — Using a config file**

Copy the example and edit values (bucket, key, region, dynamodb_table):

```bash
cp backend.hcl.example backend.hcl
# Edit backend.hcl with your bucket, key, region, dynamodb_table
terraform init -reconfigure -backend-config=backend.hcl
```

**If you have existing local state and want to migrate (not overwrite):**

```bash
terraform init -migrate-state
# When prompted, add the same -backend-config=... options as above
```

---

## Step 3: Configure auto-apply (optional)

By default, the pipeline only runs **plan** and saves the plan artifact; it does **not** apply.

To enable **auto-apply** on each push, set in `cicd/terraform.tfvars` (or `cicd/variables.tf` defaults):

```hcl
approve_apply = true
```

Then update the CICD stack (or let the pipeline do it; see below):

```bash
cd cicd && terraform apply
```

**Warning:** With `approve_apply = true`, every push to the tracked branch will run `terraform apply`. Use with care; for production, many teams keep this `false` and apply manually or via a separate approval step.

**Auto-apply cicd from the pipeline:** If you migrated cicd state to S3 (Step 1), the pipeline will **apply the cicd stack** whenever you push changes under `cicd/` (e.g. `approve_apply`, pipeline config). So you can change `cicd/terraform.tfvars` or `cicd/main.tf`, push, and the pipeline will run `terraform apply` in `cicd/` first, then run the main Terraform. No need to run `cd cicd && terraform apply` manually for cicd-only changes.

---

## Step 4: Set Terraform variables for CodeBuild

CodeBuild needs at least **`TF_VAR_mongodb_root_password`** so the main Terraform can create/update the SSM parameter used by MongoDB. This is provided via **AWS Systems Manager Parameter Store**.

**Create the parameter** (run once; use a strong password):

```bash
aws ssm put-parameter --name /mongotf/tfvar/mongodb_root_password \
  --value "YourSecurePassword" --type SecureString
```

**If the parameter already exists**, update it with:

```bash
aws ssm put-parameter --name /mongotf/tfvar/mongodb_root_password \
  --value "YourNewPassword" --type SecureString --overwrite
```

**How it’s used:** The CICD Terraform configures CodeBuild so that `TF_VAR_mongodb_root_password` is read from Parameter Store at build time. The mapping is:

- **CodeBuild env var:** `TF_VAR_mongodb_root_password`
- **Value:** `/mongotf/tfvar/mongodb_root_password`
- **Type:** `PARAMETER_STORE`

To use a **different SSM path**, set in `cicd/terraform.tfvars`:

```hcl
mongodb_password_parameter = "/your/custom/path"
```

**Other variables:** `TF_VAR_aws_account_id` and `TF_VAR_aws_region` are set automatically by the CICD module. To set `TF_VAR_environment`, add it in CodeBuild → Edit → Environment → Environment variables, or extend the `cicd` Terraform to pass it through.

---

## Step 5: Trigger the pipeline

Push to the branch the pipeline watches (e.g. `main`). **Before pushing to CodeCommit**, set your AWS profile (see [CODECOMMIT.md — Before you push](CODECOMMIT.md#before-you-push-export-aws-credentials)):

```bash
export AWS_PROFILE=mongotf
git add .
git commit -m "Terraform changes"
git push codecommit main
```

The pipeline runs: **Source (CodeCommit)** → **Build (Terraform init, validate, plan, apply if enabled).**

Pipeline triggers are set up via EventBridge (or equivalent) on push. If the pipeline does not trigger after a push, run `cd cicd && terraform apply` to ensure the EventBridge rule and pipeline are up to date.

---

## Branches and manual apply

- The pipeline watches **one branch** by default (e.g. `main`). To add staging or development, edit `cicd/main.tf` and add more source actions or pipelines per branch.
- You can still run Terraform **locally** (with the same S3 backend):

```bash
terraform plan
terraform apply
```

---

## File layout

```
.
├── buildspec.yml          # CodeBuild steps: init, validate, plan, (apply)
├── main.tf, variables.tf  # Main Terraform (MongoDB infra)
├── backend.hcl.example    # Example backend config (copy to backend.hcl)
├── cicd/
│   ├── main.tf            # Pipeline, CodeBuild, S3, DynamoDB, EventBridge
│   ├── variables.tf
│   ├── outputs.tf
│   └── backend.tf
└── CICD.md                # This file
```

---

## Troubleshooting

| Issue | What to check / do |
|-------|--------------------|
| **Pipeline not triggering on push** | Ensure EventBridge rule exists: `cd cicd && terraform apply`. Confirm `codecommit_repository_name` in `cicd` matches the CodeCommit repo name exactly (case-sensitive). |
| **Build fails: "parameter not found"** | Create the SSM parameter: `aws ssm put-parameter --name /mongotf/tfvar/mongodb_root_password --value 'YourPassword' --type SecureString`. Ensure CodeBuild role has `ssm:GetParameter` (and `kms:Decrypt` if SecureString) on that parameter. |
| **Build fails: "bucket does not exist" or "dynamodb table not found"** | Bootstrap first: `cd cicd && terraform apply`. Then run `terraform init -reconfigure` in the project root with the correct backend config. |
| **Build fails: "state locked"** | Another run or a local process holds the lock. Wait for the other run to finish, or in DynamoDB delete the lock item for the state key (use with care). |
| **Apply runs but nothing changes** | Confirm `approve_apply = true` in `cicd` and that you re-applied the cicd stack. Check CodeBuild logs for "Apply skipped (APPROVE_APPLY != true)". |
| **Wrong branch built** | In `cicd/main.tf`, the source stage specifies the branch; change it there and run `cd cicd && terraform apply`. |
| **"CICD apply skipped" in logs** | The pipeline only applies the cicd stack when `cicd/*` changed and cicd state is in S3. Run the migrate step in [Step 1](#step-1-bootstrap-the-cicd-stack) (uncomment backend block, then `terraform init -migrate-state -reconfigure`). |
