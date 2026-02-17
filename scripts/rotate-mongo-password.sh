#!/usr/bin/env sh
# Rotate MongoDB root password: update SSM, then SSH to EC2 and run changeUserPassword.
# Usage: ./rotate-mongo-password.sh [--env dev|staging|prod] [--region REGION] [--restart]
#   Prompts for new password, or set MONGO_NEW_PASSWORD in env.
#   --restart: restart mongod after changing password (optional).
# Mac/Linux/Git Bash. For Windows PowerShell use rotate-mongo-password.ps1.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV="dev"
REGION="${AWS_REGION:-eu-central-1}"
RESTART_MONGO=""

while [ $# -gt 0 ]; do
  case "$1" in
    --env)     ENV="$2"; shift 2 ;;
    --region)  REGION="$2"; shift 2 ;;
    --restart) RESTART_MONGO=1; shift ;;
    *) echo "Unknown option: $1" 1>&2; exit 1 ;;
  esac
done

# Map environment to SSM path prefix (dev, stage, prod)
case "$ENV" in
  dev)      SSM_PREFIX="dev" ;;
  staging)  SSM_PREFIX="stage" ;;
  prod)     SSM_PREFIX="prod" ;;
  *) echo "Error: --env must be dev, staging, or prod" 1>&2; exit 1 ;;
esac

SSM_PATH="/mongodb/${SSM_PREFIX}"
OUTPUTS_JSON="$PROJECT_ROOT/outputs/${SSM_PREFIX}_outputs.json"

if [ ! -f "$OUTPUTS_JSON" ]; then
  echo "Error: $OUTPUTS_JSON not found. Run Terraform apply first so outputs are written." 1>&2
  exit 1
fi

# Parse IP and key path from JSON (portable: no jq required)
EC2_IP=$(grep -o '"ec2_public_ip":"[^"]*"' "$OUTPUTS_JSON" | sed 's/.*:"\([^"]*\)"$/\1/')
KEY_PATH=$(grep -o '"ssh_private_key_path":"[^"]*"' "$OUTPUTS_JSON" | sed 's/.*:"\([^"]*\)"$/\1/')

if [ -z "$EC2_IP" ] || [ -z "$KEY_PATH" ]; then
  echo "Error: could not read ec2_public_ip or ssh_private_key_path from $OUTPUTS_JSON" 1>&2
  exit 1
fi

# Resolve key path relative to project root if needed
case "$KEY_PATH" in
  /*) ;;
  *) KEY_PATH="$PROJECT_ROOT/$KEY_PATH" ;;
esac
if [ ! -f "$KEY_PATH" ]; then
  echo "Error: SSH key not found: $KEY_PATH" 1>&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "Error: aws CLI not found" 1>&2
  exit 1
fi

# Current user and password from SSM
CURRENT_USER=$(aws ssm get-parameter --name "${SSM_PATH}/MONGO_INITDB_ROOT_USERNAME" --query Parameter.Value --output text --region "$REGION" 2>/dev/null || echo "mongolabadmin")
CURRENT_PASS=$(aws ssm get-parameter --with-decryption --name "${SSM_PATH}/MONGO_INITDB_ROOT_PASSWORD" --query Parameter.Value --output text --region "$REGION" 2>/dev/null) || { echo "Error: could not read current password from SSM" 1>&2; exit 1; }

if [ -n "$MONGO_NEW_PASSWORD" ]; then
  NEW_PASS="$MONGO_NEW_PASSWORD"
else
  echo "Enter new MongoDB root password:"
  stty -echo 2>/dev/null; read -r NEW_PASS; stty echo 2>/dev/null
  echo ""
  if [ -z "$NEW_PASS" ]; then
    echo "Error: empty password" 1>&2
    exit 1
  fi
fi

echo "Updating SSM parameter ${SSM_PATH}/MONGO_INITDB_ROOT_PASSWORD..."
aws ssm put-parameter --name "${SSM_PATH}/MONGO_INITDB_ROOT_PASSWORD" --type SecureString --value "$NEW_PASS" --overwrite --region "$REGION"

echo "Connecting to EC2 and updating MongoDB password..."
# Pass current password to remote via stdin; remote reads new from SSM and runs changeUserPassword
printf '%s' "$CURRENT_PASS" | ssh -o StrictHostKeyChecking=accept-new -i "$KEY_PATH" "ec2-user@$EC2_IP" " \
  set -e; \
  cat > /tmp/cur_pw && chmod 600 /tmp/cur_pw; \
  NEW_PW=\$(aws ssm get-parameter --with-decryption --name ${SSM_PATH}/MONGO_INITDB_ROOT_PASSWORD --query Parameter.Value --output text --region ${REGION}); \
  echo \"\$NEW_PW\" > /tmp/new_pw && chmod 600 /tmp/new_pw; \
  mongosh admin --quiet --eval \"
    const u = '${CURRENT_USER}';
    const c = require('fs').readFileSync('/tmp/cur_pw','utf8').trim();
    const n = require('fs').readFileSync('/tmp/new_pw','utf8').trim();
    db.auth(u, c);
    db.changeUserPassword(u, n);
    print('Password updated successfully.');
  \"; \
  rm -f /tmp/cur_pw /tmp/new_pw; \
  $([ -n "$RESTART_MONGO" ] && echo "sudo systemctl restart mongod; echo 'mongod restarted.';" || echo "true"); \
"

if [ -n "$RESTART_MONGO" ]; then
  echo "mongod has been restarted."
else
  echo "MongoDB password has been rotated and SSM updated. (Use --restart to restart mongod.)"
fi
echo "Use the new password to connect (e.g. from mongodb_connection_string in outputs)."
