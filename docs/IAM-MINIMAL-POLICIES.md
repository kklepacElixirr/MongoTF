# Minimal IAM Policies for MongoTF

This document explains how to configure an IAM user with the **minimum required policies** to run Terraform (main + cicd), push to CodeCommit, and manage the MongoDB infrastructure.

---

## Policy Overview

| Policy | Purpose |
|--------|---------|
| **PowerUserAccess** | Full access to most AWS services (EC2, S3, ECS, EFS, SSM, CloudWatch, CodePipeline, CodeBuild, DynamoDB, etc.) except IAM |
| **IAMFullAccess** | IAM operations required by Terraform (create roles, attach policies, etc.) |
| **AWSCodeCommitPowerUser** | Git push/pull to CodeCommit repositories |

**Use managed policies**—do not use inline policies. Inline policies have a 2,048-byte limit and will fail for complex permissions.

---

## Step-by-Step Setup

### 1. Create or Select an IAM User

- Go to **IAM** → **Users** → **Create user** (or select existing user like `codeCommitPU`)
- User name: e.g. `mongotf-terraform` or `codeCommitPU`

### 2. Attach Managed Policies (No Inline Policies)

1. Open the user → **Permissions** tab
2. Click **Add permissions** → **Attach policies directly**
3. Search and select these three policies:
   - **PowerUserAccess**
   - **IAMFullAccess**
   - **AWSCodeCommitPowerUser**
4. Click **Add permissions**

### 3. Remove Inline Policies (If Any)

If the user has inline policies that caused the 2048-byte limit error:

1. Under **Permissions** → **Inline policies**
2. For each inline policy → **Remove**

### 4. Create Access Keys (For Terraform/CLI)

1. User → **Security credentials** → **Access keys** → **Create access key**
2. Use case: **Command Line Interface (CLI)**
3. Save the Access key ID and Secret access key

### 5. Configure AWS CLI

```bash
aws configure --profile mongotf
# Access Key ID: [paste]
# Secret Access Key: [paste]
# Default region: eu-central-1
```

### 6. Configure Git for CodeCommit

```bash
git config --global credential.helper '!aws codecommit credential-helper $@'
git config --global credential.UseHttpPath true
```

When pushing, use the profile:

```bash
export AWS_PROFILE=mongotf
git push codecommit main
```

---

## What Each Policy Covers

### PowerUserAccess

- **S3**: State bucket, pipeline artifacts, versioning, encryption
- **DynamoDB**: State locking table
- **CodePipeline**: Create and manage pipelines
- **CodeBuild**: Create and manage build projects
- **EC2**: Instances, EBS, EIP, security groups, AMIs, key pairs
- **ECS**: Clusters, task definitions, services
- **EFS**: File systems, mount targets
- **SSM**: Parameter Store
- **CloudWatch**: Logs and alarms
- **Service Discovery**
- Does **not** include IAM (no role/policy creation)

### IAMFullAccess

- Create and delete IAM roles
- Attach/detach policies
- Create instance profiles
- `ListRolePolicies`, `ListInstanceProfilesForRole`, and other IAM read operations Terraform needs

### AWSCodeCommitPowerUser

- Clone, push, pull CodeCommit repositories
- Create branches, list repositories
- Works with `git-remote-codecommit` or HTTPS credential helper

---

## Security Notes

- **PowerUserAccess** is broad—it excludes IAM but allows most resource creation. For production, consider custom scoped policies.
- **IAMFullAccess** is powerful; restrict to users who genuinely need to run Terraform.
- Rotate access keys regularly and use IAM Identity Center (SSO) when possible.
- Do not commit access keys or credentials; use `terraform.tfvars` (gitignored) for sensitive values.

---

## Troubleshooting

| Error | Solution |
|-------|----------|
| `Maximum policy size of 2048 bytes exceeded` | Remove inline policies; use managed policies only |
| `not authorized to perform: iam:ListRolePolicies` | Attach **IAMFullAccess** |
| `not authorized to perform: iam:ListInstanceProfilesForRole` | Attach **IAMFullAccess** |
| `403` on `git push codecommit` | Attach **AWSCodeCommitPowerUser** and configure credential helper |
| `S3 bucket does not exist` | Run cicd bootstrap first, or create bucket manually |

---

## Quick Reference

```
User: codeCommitPU (or your user)
Managed Policies:
  - PowerUserAccess
  - IAMFullAccess
  - AWSCodeCommitPowerUser

Inline Policies: None
```
