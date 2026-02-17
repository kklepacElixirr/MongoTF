# Terraform CI/CD with CodePipeline

Automated Terraform apply via AWS CodePipeline and CodeBuild. Triggers on push to CodeCommit.

## Overview

1. **Bootstrap** (run once): Creates S3 state bucket, DynamoDB lock table, CodePipeline, CodeBuild
2. **Main project**: Uses S3 backend, applied by the pipeline (or locally)

## Prerequisites

- CodeCommit repo `MongoTF` with your Terraform code
- Terraform applied locally at least once (or pipeline will create everything)

## Step 1: Bootstrap the CI/CD

```bash
cd cicd
terraform init
terraform apply
```

This creates:

- S3 bucket for Terraform state
- DynamoDB table for state locking
- CodePipeline (source: CodeCommit, build: CodeBuild)
- CodeBuild project running `buildspec.yml`

## Step 2: Migrate main project to S3 backend

After bootstrap, initialize the main Terraform with the S3 backend. **Region is required**:

```bash
cd ..   # back to project root
terraform init -reconfigure \
  -backend-config="bucket=$(cd cicd && terraform output -raw terraform_state_bucket)" \
  -backend-config="key=$(cd cicd && terraform output -raw terraform_state_key)" \
  -backend-config="dynamodb_table=$(cd cicd && terraform output -raw terraform_lock_table)" \
  -backend-config="region=eu-central-1"
```

**Or** use a config file (copy `backend.hcl.example` to `backend.hcl`, edit values, then):

```bash
terraform init -reconfigure -backend-config=backend.hcl
```

If you have existing state locally and want to migrate (not overwrite):

```bash
terraform init -migrate-state  # add -backend-config as above when prompted
```

## Step 3: Configure auto-apply (optional)

By default, the pipeline only runs `terraform plan`. To enable auto-apply:

In `cicd/variables.tf` or `cicd/terraform.tfvars`:

```hcl
approve_apply = true
```

Then:

```bash
cd cicd && terraform apply
```

**Warning**: Auto-apply will change infrastructure on every push. Use with care; prefer manual apply for production.

## Step 4: Set Terraform variables in CodeBuild

Add these in **CodeBuild** → your project → **Edit** → **Environment** → **Additional configuration** → **Environment variables**:

| Name | Value | Type |
|------|-------|------|
| `TF_VAR_aws_account_id` | (set by pipeline) | - |
| `TF_VAR_mongodb_root_password` | Your MongoDB password | SECRETS_MANAGER or PARAMETER_STORE |
| `TF_VAR_environment` | dev / staging / prod | Plaintext |

For secrets, create an SSM parameter:

```bash
aws ssm put-parameter --name /mongotf/tfvar/mongodb_root_password \
  --value "YourSecurePassword" --type SecureString
```

Then in CodeBuild env: Name=`TF_VAR_mongodb_root_password`, Value=`/mongotf/tfvar/mongodb_root_password`, Type=`PARAMETER_STORE`

## Step 5: Trigger the pipeline

Push to `main`:

```bash
git add .
git commit -m "Terraform changes"
git push codecommit main
```

Pipeline runs: Source (CodeCommit) → Build (Terraform init, plan, apply)

## Branches

The pipeline watches `main` by default. To add staging/development, edit `cicd/main.tf` and add more source actions or pipelines per branch.

## Manual apply from local

You can still apply locally (with backend configured):

```bash
terraform plan
terraform apply
```

## File layout

```
.
├── buildspec.yml          # CodeBuild steps (init, plan, apply)
├── main.tf, variables.tf  # Main Terraform (MongoDB infra)
├── cicd/
│   ├── main.tf            # Pipeline, CodeBuild, S3, DynamoDB
│   ├── variables.tf
│   ├── outputs.tf
│   └── backend.tf
└── CICD.md                # This file
```
