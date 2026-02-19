# Minimal IAM policies for MongoTF

Minimum permissions for an IAM user to run the **main** Terraform (MongoDB on EC2, SSM, etc.).

Use **managed policies** only; inline policies have a 2,048-byte limit and can cause failures.

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
| **PowerUserAccess** | EC2, EBS, EIP, S3, SSM Parameter Store, CloudWatch, and most AWS services (excludes IAM) |
| **IAMFullAccess** | Create roles, policies, instance profiles; list operations Terraform needs |

**Do not use inline policies** for these permissions—use only **managed policies**.

---

## Step-by-step setup

### 1. Create or select an IAM user

IAM → **Users** → **Create user** (or choose an existing user, e.g. `mongotf-terraform`).

### 2. Attach managed policies

1. Open the user → **Permissions** tab.
2. **Add permissions** → **Attach policies directly**.
3. Attach:
   - **PowerUserAccess**
   - **IAMFullAccess**
4. **Add permissions**.

### 3. Remove inline policies (if any)

If you see **"Maximum policy size of 2048 bytes exceeded"**:

- Under **Permissions** → **Inline policies** → **Remove** (or move permissions into a managed policy).

### 4. Create access keys

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

### 6. Use the profile for Terraform

```bash
export AWS_PROFILE=mongotf
terraform init
terraform plan
```

---

## What each policy covers

### PowerUserAccess

- **EC2:** Instances, EBS, EIP, security groups, AMIs, key pairs.
- **SSM:** Parameter Store (create/read/update parameters).
- **S3:** Buckets (e.g. optional remote state), versioning, encryption.
- **DynamoDB:** Optional state locking table.
- **CloudWatch:** Logs and alarms.
- Does **not** include IAM (no role/policy creation).

### IAMFullAccess

- Create/delete IAM roles and policies.
- Attach/detach policies, create instance profiles.
- List operations Terraform needs (e.g. `ListRolePolicies`, `ListInstanceProfilesForRole`).

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
| **Maximum policy size of 2048 bytes exceeded** | Remove **inline** policies; use only **managed** policies. |
| **not authorized to perform: iam:ListRolePolicies** | Attach **IAMFullAccess**. |
| **not authorized to perform: iam:ListInstanceProfilesForRole** | Attach **IAMFullAccess**. |
| **S3 bucket does not exist** (during init) | Create the state bucket and optional DynamoDB table first, or use local state. |
| **Access denied (SSM)** | Ensure **PowerUserAccess** (or an SSM policy with `ssm:GetParameter`, `ssm:PutParameter`, and for SecureString: `kms:Decrypt`). |

---

## Quick reference

```
User: mongotf-terraform (or your user name)
Managed policies:
  - PowerUserAccess
  - IAMFullAccess

Inline policies: None

CLI:
  export AWS_PROFILE=mongotf
  terraform plan
```
