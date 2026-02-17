# Rotate MongoDB root password

This guide covers how to change the MongoDB root password and keep it in sync with **AWS SSM Parameter Store**: update SSM, then run `changeUserPassword` on the EC2 instance via the **rotate-mongo-password** script (or manually). It includes examples for all environments and troubleshooting.

---

## Table of contents

- [Overview](#overview)
- [Why use the script](#why-use-the-script)
- [Prerequisites](#prerequisites)
- [Usage](#usage)
- [Examples](#examples)
- [What the script does](#what-the-script-does)
- [Option B: Manual (SSH)](#option-b-manual-ssh)
- [Troubleshooting](#troubleshooting)

---

## Overview

- The **EC2 instance** reads the root password from SSM **only at first boot** (user-data). If you change the parameter later in the AWS Console, the **running** MongoDB still has the old password until you update it inside MongoDB.
- The **rotate-mongo-password** script:
  1. Reads the **current** password (and username) from SSM.
  2. Asks for a **new** password (or uses `MONGO_NEW_PASSWORD`).
  3. **Updates SSM** with the new password.
  4. **SSHs** to the EC2 instance and runs MongoDB’s `changeUserPassword` so the running process uses the new password.
- After that, SSM and the live MongoDB are in sync. New instances will pick up the new password from SSM at boot.

---

## Why use the script

- **Single command** to update both SSM and the running MongoDB.
- **Correct environment**: uses `outputs/<env>_outputs.json` so it targets the right instance and SSM path.
- **No manual SSH** or copying connection strings; the script uses the outputs file for IP and key path.

---

## Prerequisites

- **Outputs file** from a previous Terraform apply: `outputs/dev_outputs.json`, `outputs/stage_outputs.json`, or `outputs/prod_outputs.json` (script reads `ec2_public_ip` and `ssh_private_key_path`).
- **AWS CLI** configured (for SSM get/put). Same account/region as the stack.
- **SSH** and the **SSH key** referenced in the outputs file (e.g. `dev_mongo-key.pem` in the project root).
- **Network**: your IP must be allowed by the instance security group (`ssh_allowed_cidrs` in Terraform).
- **EC2 instance** running and MongoDB up (user-data finished).

---

## Usage

### Shell (Mac / Linux / Git Bash on Windows)

```bash
./scripts/rotate-mongo-password.sh [--env dev|staging|prod] [--region REGION] [--restart]
```

- **`--env`** — Environment: `dev`, `staging`, or `prod`. Chooses SSM path and outputs file (default: `dev`).
- **`--region`** — AWS region (default: `eu-central-1` or `AWS_REGION`).
- **`--restart`** — After changing the password, run `sudo systemctl restart mongod` on the instance (optional).

**New password:**

- **Interactive:** run without env; script prompts for the new password.
- **Non-interactive:** set `MONGO_NEW_PASSWORD` in the environment (avoid storing in shell history).

### PowerShell (Windows)

```powershell
.\scripts\rotate-mongo-password.ps1 [-Env dev|staging|prod] [-Region REGION] [-Restart]
```

- **`-Env`** — Same as `--env` (default: `dev`).
- **`-Region`** — Same as `--region`.
- **`-Restart`** — Same as `--restart`.
- **New password:** prompt, or set `$env:MONGO_NEW_PASSWORD`.

---

## Examples

### Example 1: Dev, interactive (prompt for new password)

```bash
./scripts/rotate-mongo-password.sh --env dev
# Enter new MongoDB root password when prompted
```

### Example 2: Staging, non-interactive and restart mongod

```bash
MONGO_NEW_PASSWORD='NewStagingPass1!' ./scripts/rotate-mongo-password.sh --env staging --restart
```

### Example 3: Prod with custom region

```bash
export MONGO_NEW_PASSWORD='NewProdPass1!'
./scripts/rotate-mongo-password.sh --env prod --region eu-west-1
```

### Example 4: Windows PowerShell, interactive

```powershell
.\scripts\rotate-mongo-password.ps1 -Env dev
```

### Example 5: Windows, non-interactive with restart

```powershell
$env:MONGO_NEW_PASSWORD = "NewSecure1!"
.\scripts\rotate-mongo-password.ps1 -Env prod -Restart
```

---

## What the script does

1. **Resolves environment**  
   Maps `--env` to SSM prefix and outputs file:
   - `dev` → `/mongodb/dev`, `outputs/dev_outputs.json`
   - `staging` → `/mongodb/stage`, `outputs/stage_outputs.json`
   - `prod` → `/mongodb/prod`, `outputs/prod_outputs.json`

2. **Reads outputs**  
   Parses `ec2_public_ip` and `ssh_private_key_path` from the JSON file. Resolves the key path relative to the project root if needed.

3. **Reads current credentials from SSM**  
   - `MONGO_INITDB_ROOT_USERNAME` (defaults to `mongolabadmin` if missing)  
   - `MONGO_INITDB_ROOT_PASSWORD` (required)

4. **Gets new password**  
   From prompt or `MONGO_NEW_PASSWORD`.

5. **Updates SSM**  
   `aws ssm put-parameter` for `MONGO_INITDB_ROOT_PASSWORD` (SecureString, overwrite).

6. **SSH and MongoDB update**  
   - Pipes current password to the remote shell (saved to a temp file).
   - Remote: fetches the new password from SSM (already updated), then runs `mongosh` to `db.auth(user, current)` and `db.changeUserPassword(user, new)`.
   - Cleans up temp files; optionally runs `sudo systemctl restart mongod` if `--restart` / `-Restart` is set.

7. **Prints**  
   Confirmation and a note to use the new password for connections.

---

## Option B: Manual (SSH)

If you prefer not to use the script:

1. **Update SSM** in the AWS Console (Parameter Store): edit `/mongodb/<env>/MONGO_INITDB_ROOT_PASSWORD` (or use `aws ssm put-parameter`).

2. **SSH** to the instance (use the key and IP from `outputs/<env>_outputs.json` or `terraform output`):

   ```bash
   ssh -i "$(terraform output -raw ssh_private_key_path)" ec2-user@$(terraform output -raw ec2_public_ip)
   ```

3. **On the instance**, connect and change the password (replace `CURRENT_PASSWORD` and `NEW_PASSWORD`; use the value you set in SSM for `NEW_PASSWORD`):

   ```bash
   mongosh "mongodb://mongolabadmin:CURRENT_PASSWORD@localhost:27017/admin" --eval "
     db.changeUserPassword('mongolabadmin', 'NEW_PASSWORD');
   "
   ```

4. Use the new password for all future connections.

---

## Troubleshooting

| Issue | Cause | What to do |
|-------|--------|------------|
| **`outputs/<env>_outputs.json not found`** | No Terraform apply for that env, or outputs not written. | Run Terraform apply for that environment so `outputs/<env_prefix>_outputs.json` exists. |
| **`could not read ec2_public_ip or ssh_private_key_path`** | Outputs file missing keys or wrong format. | Ensure the file is the one written by Terraform (contains `ec2_public_ip`, `ssh_private_key_path`). Re-run apply if needed. |
| **`SSH key not found`** | Path in outputs is wrong or key was moved/deleted. | Fix path in outputs or restore the key (e.g. `dev_mongo-key.pem` in project root). Resolve relative path from project root. |
| **`aws CLI not found`** | AWS CLI not installed or not on PATH. | Install AWS CLI and ensure it’s on PATH. |
| **`could not read current password from SSM`** | No access to SSM, wrong region, or parameter missing. | Check AWS credentials and region. Ensure parameter exists: `aws ssm get-parameter --name /mongodb/<env>/MONGO_INITDB_ROOT_PASSWORD --with-decryption --region <region>`. |
| **Permission denied (publickey)** | SSH key not used or wrong key. | Use the key path from the outputs file; run `chmod 600 <keyfile>`. Ensure your IP is in `ssh_allowed_cidrs`. |
| **Connection timed out / Connection refused** | Security group or network. | Ensure your IP is in `ssh_allowed_cidrs` in Terraform and the instance is running. Check VPC/security group if in a custom network. |
| **mongosh: command not found** (on EC2) | MongoDB not installed or not on PATH. | Wait for user-data to finish, or SSH and check `/var/log/user-data.log` and `systemctl status mongod`. |
| **Authentication failed** (MongoDB) | Current password wrong or user doesn’t exist. | Verify current password in SSM. If you changed it elsewhere, set SSM to the password the instance actually uses, then run the script again. |
| **Empty password** | Script got an empty `MONGO_NEW_PASSWORD` or empty input. | Set a non-empty password (env or prompt). Avoid leading/trailing spaces. |

### Verifying SSM after rotate

```bash
# Replace dev and region as needed
aws ssm get-parameter --name /mongodb/dev/MONGO_INITDB_ROOT_PASSWORD --with-decryption --query Parameter.Value --output text --region eu-central-1
```

### Connecting after rotate

Use the **new** password with the connection string from `outputs/<env>_outputs.json` or `terraform output mongodb_connection_string` (replace `<PASSWORD>` with the new value).
