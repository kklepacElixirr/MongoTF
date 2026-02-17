# Run Terraform apply only. Use when you changed Terraform code (main.tf, variables, etc.)
# and want to apply without creating a new instance or changing the password.
# Requires: terraform.tfvars already in place (from a previous create or manual setup).
#
# Usage: .\apply-mongo-infra.ps1 [-AutoApprove]
#   Or set $env:AUTO_APPROVE = "1" to skip the apply confirmation prompt.

$ErrorActionPreference = "Stop"

param([switch] $AutoApprove)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$Tfvars = Join-Path $ProjectRoot "terraform.tfvars"

if (-not (Test-Path $Tfvars)) {
    Write-Error "terraform.tfvars not found. Create it from an example or run create-mongo-infra.ps1 first."
    exit 1
}

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-Error "terraform not found. Install Terraform and ensure it is on PATH."
    exit 1
}

Set-Location $ProjectRoot

Write-Host "Running Terraform init..."
terraform init -reconfigure

Write-Host "Running Terraform apply..."
if ($AutoApprove -or $env:AUTO_APPROVE -match "^(1|true|yes|y)$") {
    terraform apply -auto-approve
} else {
    terraform apply
}
