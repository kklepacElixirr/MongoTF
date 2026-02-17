#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log) 2>&1

REGION="${aws_region}"

# Add the MongoDB 8.2 repository
cat <<EOT > /etc/yum.repos.d/mongodb-org-8.2.repo
[mongodb-org-8.2]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2023/mongodb-org/8.2/x86_64/
gpgcheck=0
enabled=1
EOT

dnf install -y mongodb-org

# MongoDB 8.x TCMalloc/THP: enable THP with official settings (docs/manual/administration/tcmalloc-performance)
# v8.0 requires: enabled=always, defrag=defer+madvise, max_ptes_none=0, vm.overcommit_memory=1
cat <<'SVC' > /etc/systemd/system/enable-transparent-huge-pages.service
[Unit]
Description=Enable Transparent Hugepages (THP) for MongoDB 8.x
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=mongod.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo always | tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null && echo defer+madvise | tee /sys/kernel/mm/transparent_hugepage/defrag > /dev/null && echo 0 | tee /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none > /dev/null && echo 1 | tee /proc/sys/vm/overcommit_memory > /dev/null'
RemainAfterExit=yes

[Install]
WantedBy=basic.target
SVC
systemctl daemon-reload
systemctl enable enable-transparent-huge-pages.service
systemctl start enable-transparent-huge-pages.service

# Fix MongoDB warnings: vm.max_map_count, swappiness, overcommit_memory
cat <<'SYSCTL' >> /etc/sysctl.d/99-mongodb.conf
vm.max_map_count = 1677720
vm.swappiness = 0
vm.overcommit_memory = 1
SYSCTL
sysctl -p /etc/sysctl.d/99-mongodb.conf 2>/dev/null || true

# Fix glibc rseq / tcmalloc warning: GLIBC_TUNABLES=glibc.pthread.rseq=0
mkdir -p /etc/systemd/system/mongod.service.d
cat <<'ENV' > /etc/systemd/system/mongod.service.d/environment.conf
[Service]
Environment="GLIBC_TUNABLES=glibc.pthread.rseq=0"
ENV
systemctl daemon-reload

# Configure MongoDB to listen on all interfaces (accepts remote connections)
if [ -f /etc/mongod.conf ]; then
  sed -i 's/bindIp: .*/bindIp: 0.0.0.0/' /etc/mongod.conf
  sed -i 's/bindIpAll: .*/bindIpAll: true/' /etc/mongod.conf 2>/dev/null || true
fi

# Mount EBS volume for MongoDB data (WiredTiger recommends XFS)
MONGO_DBPATH="/var/lib/mongo"
while [ ! -b /dev/nvme1n1 ] && [ ! -b /dev/xvdf ]; do echo "Waiting for EBS volume..."; sleep 2; done
DATA_DEV=$( [ -b /dev/nvme1n1 ] && echo /dev/nvme1n1 || echo /dev/xvdf )
if ! blkid "$${DATA_DEV}" | grep -q xfs; then
  mkfs.xfs -L mongodb "$${DATA_DEV}"
fi
mount "$${DATA_DEV}" "$${MONGO_DBPATH}"
echo "LABEL=mongodb $${MONGO_DBPATH} xfs defaults,nofail 0 2" >> /etc/fstab
chown -R mongod:mongod "$${MONGO_DBPATH}"
sed -i 's|dbPath:.*|dbPath: '"$${MONGO_DBPATH}"'|' /etc/mongod.conf

# Start MongoDB without auth first
systemctl start mongod
systemctl enable mongod

# Wait for MongoDB to be ready
sleep 5
for i in {1..30}; do
  if mongosh --quiet --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Fetch credentials from SSM (instance has IAM role); path is per-environment (e.g. /mongodb/dev)
ROOT_USER=$(aws ssm get-parameter --name ${ssm_path_base}/MONGO_INITDB_ROOT_USERNAME --query Parameter.Value --output text --region "$REGION" 2>/dev/null || echo "mongolabadmin")
ROOT_PASS=$(aws ssm get-parameter --with-decryption --name ${ssm_path_base}/MONGO_INITDB_ROOT_PASSWORD --query Parameter.Value --output text --region "$REGION")

# Create admin user (write creds to temp files to handle special chars in password)
echo "$ROOT_USER" > /tmp/mongo_user
echo "$ROOT_PASS" > /tmp/mongo_pass
chmod 600 /tmp/mongo_user /tmp/mongo_pass

mongosh admin --quiet <<'MONGO_SCRIPT'
const user = require('fs').readFileSync('/tmp/mongo_user', 'utf8').trim();
const pass = require('fs').readFileSync('/tmp/mongo_pass', 'utf8').trim();
db.createUser({user: user, pwd: pass, roles: ['root']});
MONGO_SCRIPT

rm -f /tmp/mongo_user /tmp/mongo_pass

# Enable authentication in mongod.conf
if ! grep -q "authorization: enabled" /etc/mongod.conf; then
  if grep -q "^security:" /etc/mongod.conf; then
    sed -i '/^security:/a\  authorization: enabled' /etc/mongod.conf
  else
    echo -e "\nsecurity:\n  authorization: enabled" >> /etc/mongod.conf
  fi
fi

# Restart MongoDB with auth enabled
systemctl restart mongod
sleep 2

echo "MongoDB setup complete with authentication enabled"
