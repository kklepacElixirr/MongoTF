# Minimal IAM policies for MongoTF

This document describes how to give an IAM user the **minimum required permissions** to:

- Run the **main** Terraform (MongoDB on EC2, ECS, SSM, etc.)
- Run the **cicd** Terraform (CodePipeline, CodeBuild, S3 state, DynamoDB)
- Push and pull from **CodeCommit**

Use **managed policies** only. Inline policies have a 2,048-byte limit and can cause failures.

---

## Table of contents

- [Policy overview](#policy-overview)
- [Step-by-step setup](#step-by-step-setup)
- [What each policy covers](#what-each-policy-covers)
- [Security notes](#security-notes)
- [Troubleshooting](#troubleshooting)
- [Quick reference](#quick-reference)

---

## Policy overview

| Policy | Purpose |
|--------|---------|
| **PowerUserAccess** | Broad access to most AWS services (EC2, S3, ECS, EFS, SSM, CloudWatch, CodePipeline, CodeBuild, DynamoDB, etc.); **excludes IAM** |
| **IAMFullAccess** | IAM operations Terraform needs (create roles, attach policies, instance profiles, list role policies, etc.) |
| **AWSCodeCommitPowerUser** | Git push/pull and repo operations for CodeCommit |

**Do not use inline policies** for these permissions—use only **managed policies** to avoid the 2,048-byte limit.

---

## Step-by-step setup

### 1. Create or select an IAM user

- IAM → **Users** → **Create user** (or choose an existing user, e.g. `mongotf-terraform`).
- No need to add the user to a group if you attach policies directly.

### 2. Attach managed policies

1. Open the user → **Permissions** tab.
2. **Add permissions** → **Attach policies directly**.
3. Search and attach:
   - **PowerUserAccess**
   - **IAMFullAccess**
   - **AWSCodeCommitPowerUser**
4. **Add permissions**.

### 3. Remove inline policies (if any)

If you see errors like **"Maximum policy size of 2048 bytes exceeded"**:

1. Under **Permissions** → **Inline policies**.
2. For each inline policy → **Remove** (or move the needed permissions into a managed policy).

### 4. Create access keys (for Terraform / CLI)

1. User → **Security credentials** → **Access keys** → **Create access key**.
2. Use case: **Command Line Interface (CLI)**.
3. Store the Access key ID and Secret access key securely.

### 5. Configure AWS CLI

```bash
aws configure --profile mongotf
# Access Key ID: [paste]
# Secret Access Key: [paste]
# Default region: eu-central-1
```

### 6. Use the profile for Terraform and Git

**Terraform:**

```bash
export AWS_PROFILE=mongotf
terraform init
terraform plan
```

**CodeCommit (git-remote-codecommit):**

```bash
export AWS_PROFILE=mongotf
git push codecommit main
```

Optional: set credential helper so Git uses AWS for CodeCommit HTTPS:

```bash
git config --global credential.helper '!aws codecommit credential-helper $@'
git config --global credential.UseHttpPath true
```

---

## What each policy covers

### PowerUserAccess

- **S3:** State bucket, pipeline artifacts, versioning, encryption.
- **DynamoDB:** State locking table.
- **CodePipeline / CodeBuild:** Create and manage pipelines and build projects.
- **EC2:** Instances, EBS, EIP, security groups, AMIs, key pairs.
- **ECS:** Clusters, task definitions, services.
- **EFS:** File systems, mount targets.
- **SSM:** Parameter Store (create/read/update parameters).
- **CloudWatch:** Logs and alarms.
- Does **not** include IAM (no role/policy creation).

### IAMFullAccess

- Create/delete IAM roles and policies.
- Attach/detach policies, create instance profiles.
- List operations Terraform needs (e.g. `ListRolePolicies`, `ListInstanceProfilesForRole`).

### AWSCodeCommitPowerUser

- Clone, push, pull CodeCommit repositories.
- Create branches, list repositories.
- Works with `git-remote-codecommit` or HTTPS credential helper.

---

## Security notes

- **PowerUserAccess** is broad; for production, consider custom scoped policies per service.
- **IAMFullAccess** is powerful; restrict to users or roles that must run Terraform.
- Rotate access keys regularly; prefer IAM Identity Center (SSO) where possible.
- Do not commit credentials; use `terraform.tfvars` (gitignored) and SSM for secrets.

---

## Troubleshooting

| Error | Solution |
|-------|----------|
| **Maximum policy size of 2048 bytes exceeded** | Remove **inline** policies; use only **managed** policies (PowerUserAccess, IAMFullAccess, AWSCodeCommitPowerUser). |
| **not authorized to perform: iam:ListRolePolicies** | Attach **IAMFullAccess**. |
| **not authorized to perform: iam:ListInstanceProfilesForRole** | Attach **IAMFullAccess**. |
| **403 on `git push codecommit`** | Attach **AWSCodeCommitPowerUser**. Ensure `AWS_PROFILE` is set or credential helper is configured. |
| **S3 bucket does not exist** (during Terraform init) | Run the **cicd** bootstrap first: `cd cicd && terraform apply`. Then run `terraform init -reconfigure` in the project root with the backend config. |
| **Access denied (SSM)** | Ensure the user has **PowerUserAccess** (or an SSM policy that allows `ssm:GetParameter`, `ssm:PutParameter`, and if using SecureString, `kms:Decrypt`/`kms:GenerateDataKey`). |

---

## Quick reference

```
User: mongotf-terraform (or your user name)
Managed policies:
  - PowerUserAccess
  - IAMFullAccess
  - AWSCodeCommitPowerUser

Inline policies: None

CLI:
  export AWS_PROFILE=mongotf
  terraform plan
  git push codecommit main
```
