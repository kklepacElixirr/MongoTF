# MongoDB on AWS (Terraform)

Terraform module that provisions **MongoDB 8.2** on a single EC2 instance with EBS-backed persistence, Elastic IP, and optional ECS task definition for containerized MongoDB.

---

## Table of contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [Configuration](#configuration)
- [Connecting to MongoDB](#connecting-to-mongodb)
- [Integration (Payload CMS / Hasura)](#integration-payload-cms--hasura)
- [Redeploy and teardown](#redeploy-and-teardown)
- [SSH access](#ssh-access)
- [Changing the MongoDB password](#changing-the-mongodb-password)
- [Security](#security)
- [Related documentation](#related-documentation)
- [Outputs](#outputs)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Architecture

| Component | Description |
|-----------|-------------|
| **EC2** | Amazon Linux 2023; MongoDB 8.2 installed via `user-data.sh` at boot |
| **EBS** | Encrypted gp3 volume for `/var/lib/mongo` (data persists across instance replacement) |
| **Elastic IP** | Static public IP used in the connection string |
| **Auth** | Root credentials in **AWS SSM Parameter Store** (`/mongodb/MONGO_INITDB_*`), fetched at instance boot and by ECS tasks |

---

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) **>= 1.14.5**
- **AWS CLI** configured (credentials or SSO)
- AWS region with a default VPC (or adapt `main.tf` for a custom VPC)

---

## Quick start

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set aws_account_id, mongodb_root_password, and restrict CIDRs for production
terraform init
terraform apply
```

After apply, get the connection details:

```bash
terraform output ec2_public_ip
terraform output mongodb_connection_string
```

---

## Configuration

| File | Purpose |
|------|---------|
| `terraform.tfvars` | Your values (create from `terraform.tfvars.example`; **do not commit**) |
| `terraform.tfvars.example` | Template with all variables and comments |

**Required for first run:**

- `aws_account_id` — Must match the account your AWS credentials resolve to (12 digits; validated by Terraform).
- `mongodb_root_password` — Initial password; stored in SSM. Change it in AWS Console after first apply (Terraform ignores subsequent value changes).

**Recommended for production:**

- `ssh_allowed_cidrs` — e.g. `["YOUR_IP/32"]` (get your IP: `curl -s ifconfig.me`).
- `mongodb_allowed_cidrs` — Same; restrict to your IP or VPN.

Example snippet for `terraform.tfvars`:

```hcl
aws_account_id = "123456789012"
aws_region     = "eu-central-1"
environment    = "dev"

mongodb_root_username = "mongolabadmin"
mongodb_root_password = "YourSecurePassword123!"
mongodb_database      = "mongolab"

# Production: restrict to your IP
ssh_allowed_cidrs     = ["203.0.113.50/32"]
mongodb_allowed_cidrs = ["203.0.113.50/32"]
```

---

## Connecting to MongoDB

**Get the public IP:**

```bash
terraform output -raw ec2_public_ip
```

**Connect with `mongosh`** (replace `USERNAME`, `PASSWORD`, and `IP` with your values from `terraform.tfvars` and the output above):

```bash
mongosh 'mongodb://USERNAME:PASSWORD@IP:27017'
```

**Example connection string:**

```
mongodb://mongolabadmin:YourPassword@18.158.143.228:27017
```

**Connection string template** (Terraform output; replace `<PASSWORD>`):

```bash
terraform output mongodb_connection_string
```

---

## Integration (Payload CMS / Hasura)

Set the MongoDB host in your app environment (e.g. Hasura `.env.dev` or `.env`) to the EC2 public IP:

```bash
terraform output -raw ec2_public_ip
```

In `hasura/.env.dev` (or equivalent):

```env
MONGO_IP=18.158.143.228
MONGO_USER=mongolabadmin
MONGO_PASSWORD=<from terraform.tfvars or SSM>
MONGO_DB=payload
```

The CMS and build will connect to this MongoDB instance.

---

## Redeploy and teardown

**Replace EC2 instance** (keeps Elastic IP and EBS data; picks up AMI/user-data changes):

```bash
terraform taint aws_instance.mongolab_ec2_instance
terraform apply
```

**Full teardown:**

```bash
terraform destroy
```

---

## SSH access

Terraform generates an SSH key and saves it as `mongo-key.pem`:

```bash
chmod 600 mongo-key.pem
ssh -i mongo-key.pem ec2-user@$(terraform output -raw ec2_public_ip)
```

---

## Changing the MongoDB password

The instance reads the root password from **Parameter Store** only **at first boot** (in user-data). If you change **`/mongodb/MONGO_INITDB_ROOT_PASSWORD`** in SSM later, the running MongoDB still has the old password until you update it.

1. **SSH in** (use the password that currently works):
   ```bash
   ssh -i mongo-key.pem ec2-user@$(terraform output -raw ec2_public_ip)
   ```

2. **Connect and set the new password** (replace `CURRENT_PASSWORD` and `NEW_PASSWORD`; use the value you set in Parameter Store for `NEW_PASSWORD`):
   ```bash
   mongosh "mongodb://mongolabadmin:CURRENT_PASSWORD@localhost:27017/admin" --eval "
     db.changeUserPassword('mongolabadmin', 'NEW_PASSWORD');
   "
   ```

3. From then on, use the new password. New instances will pick up the new value from SSM at boot.

---

## Security

- **Restrict access:** Set `ssh_allowed_cidrs` and `mongodb_allowed_cidrs` to your IP (e.g. `["1.2.3.4/32"]`) in `terraform.tfvars` for production.
- **Change password after first apply:** Update the SSM parameter **`/mongodb/MONGO_INITDB_ROOT_PASSWORD`** in AWS Console (Systems Manager → Parameter Store). Terraform ignores changes to the parameter value. **The instance only reads this at first boot**—so after you change SSM, you must apply the new password on the running MongoDB (see [Changing the MongoDB password](#changing-the-mongodb-password)).

---

## Related documentation

| Document | Description |
|----------|-------------|
| [docs/IAM-MINIMAL-POLICIES.md](docs/IAM-MINIMAL-POLICIES.md) | Minimal IAM policies for Terraform |

---

## Outputs

| Output | Description |
|--------|-------------|
| `ec2_public_ip` | Elastic IP for MongoDB connection |
| `mongodb_connection_string` | Connection string template (replace `<PASSWORD>`) |
| `ssh_private_key_path` | Path to generated SSH key (`mongo-key.pem`) |

---

## Troubleshooting

| Issue | What to check / do |
|-------|--------------------|
| **`aws_account_id must be exactly 12 digits`** | Set `aws_account_id` in `terraform.tfvars` to your 12-digit account ID. Get it: `aws sts get-caller-identity --query Account --output text`. |
| **MongoDB connection refused** | Ensure security group allows your IP on port 27017 (`mongodb_allowed_cidrs`). Wait a few minutes after apply for user-data to finish installing MongoDB. |
| **SSH "Permission denied"** | Use `ssh -i mongo-key.pem ec2-user@...` and ensure `mongo-key.pem` has mode `600`. Confirm your IP is in `ssh_allowed_cidrs`. |
| **Password not working** | If you changed the password in SSM, the running instance still has the old one until you apply it: SSH in and run `db.changeUserPassword()` (see [Changing the MongoDB password](#changing-the-mongodb-password)). |
| **State / backend errors** | If using remote state, run `terraform init -reconfigure` with the correct backend config. |

---

## License

MIT
