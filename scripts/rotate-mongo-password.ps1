# Rotate MongoDB root password: update SSM, then SSH to EC2 and run changeUserPassword.
# Usage: .\rotate-mongo-password.ps1 [-Env dev|staging|prod] [-Region REGION] [-Restart]
#   Prompts for new password, or set $env:MONGO_NEW_PASSWORD.
$ErrorActionPreference = "Stop"

param(
    [ValidateSet("dev", "staging", "prod")]
    [string] $Env = "dev",
    [string] $Region = $env:AWS_REGION,
    [switch] $Restart
)

if (-not $Region) { $Region = "eu-central-1" }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$SSMPrefix = switch ($Env) { "dev" { "dev" }; "staging" { "stage" }; "prod" { "prod" } }
$SSMPath = "/mongodb/$SSMPrefix"
$OutputsJson = Join-Path $ProjectRoot "outputs" "${SSMPrefix}_outputs.json"

if (-not (Test-Path $OutputsJson)) {
    Write-Error "Outputs file not found: $OutputsJson. Run Terraform apply first."
    exit 1
}

$outputs = Get-Content $OutputsJson -Raw | ConvertFrom-Json
$EC2IP = $outputs.ec2_public_ip
$KeyPath = $outputs.ssh_private_key_path

if (-not [System.IO.Path]::IsPathRooted($KeyPath)) {
    $KeyPath = Join-Path $ProjectRoot $KeyPath
}
if (-not (Test-Path $KeyPath)) {
    Write-Error "SSH key not found: $KeyPath"
    exit 1
}

$CurrentUser = aws ssm get-parameter --name "${SSMPath}/MONGO_INITDB_ROOT_USERNAME" --query Parameter.Value --output text --region $Region 2>$null
if (-not $CurrentUser) { $CurrentUser = "mongolabadmin" }
$CurrentPass = aws ssm get-parameter --with-decryption --name "${SSMPath}/MONGO_INITDB_ROOT_PASSWORD" --query Parameter.Value --output text --region $Region
if (-not $CurrentPass) {
    Write-Error "Could not read current password from SSM"
    exit 1
}

if ($env:MONGO_NEW_PASSWORD) {
    $NewPass = $env:MONGO_NEW_PASSWORD
} else {
    $sec = Read-Host "Enter new MongoDB root password" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    $NewPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    if (-not $NewPass) {
        Write-Error "Empty password"
        exit 1
    }
}

Write-Host "Updating SSM parameter ${SSMPath}/MONGO_INITDB_ROOT_PASSWORD..."
aws ssm put-parameter --name "${SSMPath}/MONGO_INITDB_ROOT_PASSWORD" --type SecureString --value $NewPass --overwrite --region $Region | Out-Null

# Build remote script: save current from stdin, get new from SSM, run mongosh, optionally restart
$RemoteScript = @"
set -e
cat > /tmp/cur_pw && chmod 600 /tmp/cur_pw
NEW_PW=`$(aws ssm get-parameter --with-decryption --name $SSMPath/MONGO_INITDB_ROOT_PASSWORD --query Parameter.Value --output text --region $Region)
echo "`$NEW_PW" > /tmp/new_pw && chmod 600 /tmp/new_pw
mongosh admin --quiet --eval "
  const u = '$CurrentUser';
  const c = require('fs').readFileSync('/tmp/cur_pw','utf8').trim();
  const n = require('fs').readFileSync('/tmp/new_pw','utf8').trim();
  db.auth(u, c);
  db.changeUserPassword(u, n);
  print('Password updated successfully.');
"
rm -f /tmp/cur_pw /tmp/new_pw
"@

if ($Restart) {
    $RemoteScript += "`nsudo systemctl restart mongod; echo 'mongod restarted.'"
}

Write-Host "Connecting to EC2 and updating MongoDB password..."
$CurrentPass | & ssh -o StrictHostKeyChecking=accept-new -i $KeyPath "ec2-user@$EC2IP" $RemoteScript

if ($Restart) { Write-Host "mongod has been restarted." }
else { Write-Host "MongoDB password has been rotated and SSM updated. (Use -Restart to restart mongod.)" }
Write-Host "Use the new password to connect (e.g. from mongodb_connection_string in outputs)."
