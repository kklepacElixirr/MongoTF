# AWS CodeCommit Setup

This Terraform creates an optional CodeCommit repository. After `terraform apply`, push your code and use CodeCommit as the remote source.

## 1. Create the repo (first apply)

Ensure in `terraform.tfvars`:
```hcl
create_codecommit_repository = true
codecommit_repository_name   = "mongotf"
```

Then:
```bash
terraform apply
```

Note the outputs:
```bash
terraform output codecommit_clone_url_https
terraform output codecommit_clone_url_ssh
```

## 2. Authenticate with CodeCommit

### Option A: git-remote-codecommit (recommended, uses AWS credentials)

```bash
pip install git-remote-codecommit
```

Add CodeCommit as a remote and push (replace `eu-central-1` and `mongotf` if you use different region/repo name):
```bash
git remote add codecommit codecommit::eu-central-1://mongotf
```

### Option B: IAM HTTPS credentials

1. In IAM → Users → Your user → Security credentials → HTTPS Git credentials for AWS CodeCommit → Generate
2. Use the generated username/password with the HTTPS clone URL

### Option C: SSH

1. Add your SSH public key in IAM → Users → SSH keys for AWS CodeCommit
2. Use the SSH clone URL from the Terraform output

## 3. Push from GitHub (migration)

If you're migrating from GitHub (replace region and repo name if needed):

```bash
git remote add codecommit codecommit::eu-central-1://mongotf
git push codecommit main
git push codecommit staging
git push codecommit development
```

Then switch the default remote:

```bash
git remote set-url origin codecommit::eu-central-1://mongotf
git remote remove codecommit  # optional, if you renamed origin
```

## 4. Disable CodeCommit

Set in `terraform.tfvars`:
```hcl
create_codecommit_repository = false
```

Apply to remove the repository (CodeCommit deletes the repo and its contents).
