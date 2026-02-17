#!/usr/bin/env sh
# Run Terraform apply only. Use when you changed Terraform code (main.tf, variables, etc.)
# and want to apply without creating a new instance or changing the password.
# Requires: terraform.tfvars already in place (from a previous create or manual setup).
#
# Usage: ./apply-mongo-infra.sh [--auto-approve]
#   Or set AUTO_APPROVE=1 to skip the apply confirmation prompt.
# Mac/Linux/Git Bash. Windows: use apply-mongo-infra.ps1.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TFVARS="$PROJECT_ROOT/terraform.tfvars"

cd "$PROJECT_ROOT"

if [ ! -f "$TFVARS" ]; then
  echo "Error: terraform.tfvars not found. Create it from an example (e.g. terraform.tfvars.example.dev) or run create-mongo-infra.sh first." 1>&2
  exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "Error: terraform not found. Install Terraform and ensure it is on PATH." 1>&2
  exit 1
fi

echo "Running Terraform init..."
terraform init -reconfigure
echo "Running Terraform apply..."
case "${AUTO_APPROVE}" in 1|true|yes|y) terraform apply -auto-approve ;; *) terraform apply ;; esac
