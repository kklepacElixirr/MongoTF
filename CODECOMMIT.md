# AWS CodeCommit setup

This project can create an **optional** CodeCommit repository via Terraform. After the repo exists, you push your code and use CodeCommit as the remote source for CI/CD (e.g. CodePipeline).

---

## Table of contents

- [When to use CodeCommit](#when-to-use-codecommit)
- [1. Create the repo (first apply)](#1-create-the-repo-first-apply)
- [2. Authenticate with CodeCommit](#2-authenticate-with-codecommit)
- [3. Push from GitHub (migration)](#3-push-from-github-migration)
- [4. Disable or remove CodeCommit](#4-disable-or-remove-codecommit)
- [Troubleshooting](#troubleshooting)

---

## When to use CodeCommit

- You want **CodePipeline** to use CodeCommit as the source (no GitHub/GitLab integration).
- You prefer a single AWS account for code and infra.
- You are migrating from GitHub/GitLab and want a one-time or ongoing mirror.

If you already use GitHub and want Pipeline to pull from GitHub instead, you can leave `create_codecommit_repository = false` and configure the pipeline source for GitHub (not covered in this doc).

---

## 1. Create the repo (first apply)

In the **main** project’s `terraform.tfvars` (not `cicd/`), set:

```hcl
create_codecommit_repository = true
codecommit_repository_name   = "MongoTF"
```

Use the exact repo name you want (e.g. `MongoTF`). **Important:** The name is case-sensitive and must match **`codecommit_repository_name`** in `cicd/terraform.tfvars` so the pipeline can connect to the same repo.

Then apply the **main** Terraform (not the cicd one):

```bash
terraform apply
```

After apply, note the clone URLs:

```bash
terraform output codecommit_clone_url_https
terraform output codecommit_clone_url_ssh
```

---

## 2. Authenticate with CodeCommit

Choose one method.

### Option A: git-remote-codecommit (recommended)

Uses your AWS credentials; no separate Git username/password.

**Install:**

```bash
pip install git-remote-codecommit
```

**Add remote and push** (replace `eu-central-1` with your region if different; repo name must match exactly, e.g. `MongoTF`):

```bash
git remote add codecommit codecommit::eu-central-1://MongoTF
git push codecommit main
```

### Option B: IAM HTTPS credentials

1. IAM → **Users** → your user → **Security credentials** → **HTTPS Git credentials for AWS CodeCommit** → **Generate**.
2. Use the generated username and password with the **HTTPS** clone URL when Git prompts (e.g. `git clone https://...` or `git push codecommit main`).

### Option C: SSH

1. IAM → **Users** → your user → **SSH keys for AWS CodeCommit** → **Upload SSH public key**.
2. Clone or add remote using the **SSH** URL from `terraform output codecommit_clone_url_ssh`.

---

## 3. Push from GitHub (migration)

If your code is in GitHub and you want it in CodeCommit (e.g. for the pipeline):

**Add CodeCommit remote and push** (replace region if needed; use your repo name, e.g. `MongoTF`):

```bash
git remote add codecommit codecommit::eu-central-1://MongoTF
git push codecommit main
git push codecommit staging    # if you have these branches
git push codecommit development
```

**Optional — make CodeCommit the default remote:**

```bash
git remote set-url origin codecommit::eu-central-1://MongoTF
git remote remove codecommit   # optional, if you now use origin for CodeCommit
```

---

## 4. Disable or remove CodeCommit

To **stop creating** the repo (e.g. you use an existing repo created outside this Terraform), set in the **main** `terraform.tfvars`:

```hcl
create_codecommit_repository = false
```

Then run `terraform apply`. Terraform will plan to destroy the CodeCommit repository. **Warning:** Destroying the resource deletes the repo and **all its contents**. Only do this if you no longer need the repo or have pushed it elsewhere.

---

## Troubleshooting

| Issue | What to check / do |
|-------|--------------------|
| **Pipeline can’t find repo / wrong repo** | Ensure **`cicd`** `codecommit_repository_name` matches the repo name **exactly** (case-sensitive). Example: repo `MongoTF` → `codecommit_repository_name = "MongoTF"` in `cicd/terraform.tfvars`. |
| **`git push codecommit main` asks for password** | With `git-remote-codecommit`, ensure AWS credentials are available (`aws sts get-caller-identity` works). Configure profile: `export AWS_PROFILE=yourprofile`. |
| **403 / access denied on push** | Attach **AWSCodeCommitPowerUser** (or equivalent) to the IAM user/role. See [docs/IAM-MINIMAL-POLICIES.md](docs/IAM-MINIMAL-POLICIES.md). |
| **Repo not in Terraform output** | Confirm `create_codecommit_repository = true` and that you applied the **main** Terraform (not only `cicd`). Run `terraform output` in the project root. |
| **Want to keep code but remove repo from Terraform** | Set `create_codecommit_repository = false` and apply. Note: Terraform will destroy the repo and its contents. Back up or push to another remote first if needed. |
