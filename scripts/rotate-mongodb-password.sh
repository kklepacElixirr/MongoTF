#!/bin/bash
# Run on EC2 via SSM Run Command. Reads current password and MONGO_INITDB_ROOT_PASSWORD_NEW from SSM,
# updates MongoDB with changeUserPassword, then updates SSM and deletes _NEW param.
set -e
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
CURRENT=$(aws ssm get-parameter --with-decryption --name /mongodb/MONGO_INITDB_ROOT_PASSWORD --query Parameter.Value --output text --region "$REGION")
NEW=$(aws ssm get-parameter --with-decryption --name /mongodb/MONGO_INITDB_ROOT_PASSWORD_NEW --query Parameter.Value --output text --region "$REGION")
ROOT_USER=$(aws ssm get-parameter --name /mongodb/MONGO_INITDB_ROOT_USERNAME --query Parameter.Value --output text --region "$REGION")
echo "$NEW" > /tmp/newpass
chmod 600 /tmp/newpass
mongosh "mongodb://${ROOT_USER}:${CURRENT}@localhost:27017/admin" --eval "db.changeUserPassword('${ROOT_USER}', require('fs').readFileSync('/tmp/newpass','utf8').trim())"
aws ssm put-parameter --name /mongodb/MONGO_INITDB_ROOT_PASSWORD --value "$NEW" --type SecureString --overwrite --region "$REGION"
aws ssm delete-parameter --name /mongodb/MONGO_INITDB_ROOT_PASSWORD_NEW --region "$REGION"
rm -f /tmp/newpass
echo "MongoDB password rotated successfully."
