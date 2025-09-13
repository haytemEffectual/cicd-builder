# cicd-builder

Scaffold a **Terraform repository** with a **GitHub Actions CI/CD pipeline** on AWS using **GitHub OIDC** (no long-lived AWS keys), **remote state in S3**, and **optional DynamoDB locks**—all in a few scripted steps.

- CI on PRs: `fmt`, `init`, `validate`, (optional) `tflint`/`checkov`), and `plan`
- CD on `main`: gated `apply` (with GitHub Environments for approval)
- AWS access via **OIDC** (`permissions: id-token: write`) instead of static keys
- Branch protection ready (recommend enabling it on `main`)

> For deeper dives, see `GH_OIDC_rundown.md` (OIDC trust + role details) and `cicd_step_by_step_terraform_repo.md` (walkthrough).

---

## Prerequisites

- **GitHub**
  - An empty or new repo where you’ll run these scripts
  - Admin ability to set **Actions → Secrets/Variables**, **Environments**, and **branch protection**
- **AWS**
  - Permissions to create: **S3 bucket**, **(optional) DynamoDB table**, **OIDC provider**, **IAM role + policy**
- **Local tooling**
  - `bash`, `git`, `aws` CLI (configured to your target account), and optionally `jq`

---

## What the scripts do

The `scripts/` folder automates both the **Terraform repo structure** and the **AWS/GitHub plumbing** needed for CI/CD:

- Create a minimal Terraform folder structure (providers, versions, backend)
- Bootstrap AWS resources for state + IAM/OIDC trust for GitHub
- Wire up GitHub repo secrets/vars and drop a working workflow YAML

---

## Quick Start (5 Steps)

> Run these from the repo root. Review each script before executing in your environment.

### 1) Fill variables
Edit **`scripts/0-variables.sh`** with your values (region, repo, AWS account, bucket names, etc.).

```bash
# Example fields you’ll typically set:
GITHUB_OWNER="your-org-or-user"
GITHUB_REPO="your-repo"
AWS_ACCOUNT_ID="123456789012"
AWS_REGION="us-west-2"
TF_BACKEND_BUCKET="your-tfstate-bucket-name"
TF_LOCK_TABLE="terraform-locks"     # optional; empty to skip
OIDC_ROLE_NAME="github-oidc-terraform"
# ...and any other repo/env-specific values referenced by the other scripts
```

> Tip: Commit a company-safe version of this file (without secrets). Values like role ARN are set via GitHub **Secrets/Variables** in later steps.

---

### 2) Scaffold Terraform repo structure
Run **`scripts/1-repo_structure.sh`** to create and push a minimal Terraform layout.

```bash
bash scripts/1-repo_structure.sh
```

This typically:
- Creates `main.tf`, `providers.tf`, `versions.tf`, and backend stubs
- Adds a sample module or root configuration
- Commits and pushes the structure to your repo

---

### 3) Bootstrap AWS + CI/CD foundations (one-time)
Run **`scripts/2-bootstrap_tf.sh`** to:
- **Create S3 bucket** (remote backend for state)
- **Create DynamoDB table** (optional state locking)
- **Create AWS OIDC provider** for GitHub and its **IAM role** with a trust policy limiting which repos/branches may assume it

```bash
bash scripts/2-bootstrap_tf.sh
```

> Results: You’ll get an IAM Role ARN (e.g., `arn:aws:iam::<acct>:role/github-oidc-terraform`) and the backend resources ready for `terraform init`.

---

### 4) Set GitHub Variables & Secrets
Run **`scripts/3-variables.sh`** to wire your repo’s **Actions → Secrets/Variables**:

- **Secrets**
  - `AWS_ROLE_TO_ASSUME` → *the IAM Role ARN created in Step 3*
- **Variables**
  - `AWS_REGION` → e.g., `us-west-2`
  - `TF_BACKEND_BUCKET` → your S3 bucket
  - `TF_BACKEND_DYNAMODB_TABLE` → your lock table (or leave empty if unused)

```bash
bash scripts/3-variables.sh
```

This script uses the GitHub API/CLI (depending on your implementation) to set these centrally for your workflows.

---

### 5) Install the CI/CD workflow
Run **`scripts/4-workflow.sh`** to lay down `.github/workflows/terraform.yml` and commit it.

```bash
bash scripts/4-workflow.sh
```

A typical workflow includes:

```yaml
name: Terraform CI/CD

on:
  pull_request:
    branches: [ main ]
  push:
    branches: [ main ]

permissions:
  id-token: write   # enables GitHub→AWS OIDC
  contents: read

env:
  AWS_REGION: ${{ vars.AWS_REGION }}
  TF_BACKEND_BUCKET: ${{ vars.TF_BACKEND_BUCKET }}
  TF_BACKEND_DYNAMODB_TABLE: ${{ vars.TF_BACKEND_DYNAMODB_TABLE }}

jobs:
  validate_and_plan:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_TO_ASSUME }}
          aws-region: ${{ env.AWS_REGION }}
      - uses: hashicorp/setup-terraform@v3
      - run: terraform fmt -check -recursive
      - run: |
          terraform init             -backend-config="bucket=${TF_BACKEND_BUCKET}"             -backend-config="dynamodb_table=${TF_BACKEND_DYNAMODB_TABLE}"             -backend-config="region=${AWS_REGION}"
      - run: terraform validate
      - run: terraform plan -no-color

  apply_main:
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: prod       # require approvals in GitHub → Environments
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_TO_ASSUME }}
          aws-region: ${{ env.AWS_REGION }}
      - uses: hashicorp/setup-terraform@v3
      - run: |
          terraform init             -backend-config="bucket=${TF_BACKEND_BUCKET}"             -backend-config="dynamodb_table=${TF_BACKEND_DYNAMODB_TABLE}"             -backend-config="region=${AWS_REGION}"
      - run: terraform apply -auto-approve -input=false
```

> **Why `id-token: write`?** It lets the workflow request an OIDC token from GitHub, which AWS verifies to permit assuming your IAM role—no static AWS keys needed.

---

## After the 5 Steps

1. **Protect `main`**: GitHub → Settings → Branches → Branch protection rules  
   Require PR reviews and passing checks before merging.
2. **Create a PR** with a small Terraform change.  
   CI should run `fmt/validate/plan` and show the plan in the job logs.
3. **Merge to `main`** to trigger the **apply** (with environment approval if you configured one).

---

## Environments & Workspaces (optional patterns)

- **GitHub Environments**: Use `environment: dev` / `environment: prod` to require approvals per target.
- **Terraform Workspaces**: If you prefer, set `TF_WORKSPACE` as a variable and run `terraform workspace select $TF_WORKSPACE` in steps.

---

## Troubleshooting

- **Cannot assume role**  
  - Check the OIDC **trust policy** repo/branch conditions and that `permissions: id-token: write` is present.
- **Backend init errors**  
  - Ensure the bucket/table exist and you passed `-backend-config=...` values during `terraform init`.
- **Apply blocked**  
  - Confirm you’re pushing to `main`, the workflow includes `environment: prod`, and approvals are configured in **Environments**.

---

## File Map (key items)

- `scripts/0-variables.sh` — Fill me first (org/repo/AWS/account/bucket/role names)
- `scripts/1-repo_structure.sh` — Create & push Terraform folder structure
- `scripts/2-bootstrap_tf.sh` — Provision S3/DynamoDB, OIDC provider, IAM role
- `scripts/3-variables.sh` — Set GitHub repo Variables & Secrets
- `scripts/4-workflow.sh` — Install CI/CD workflow YAML
- `.github/workflows/terraform.yml` — The pipeline itself
- `GH_OIDC_rundown.md` — OIDC trust/role deep dive
- `cicd_step_by_step_terraform_repo.md` — Long-form guide

---

## Notes & Safety

- Limit your IAM role’s permissions to only what Terraform needs (plus S3/DynamoDB for state).
- Constrain the OIDC trust to specific repo **and** branches/tags using conditions.
- Use **required reviewers** on `prod` environment to guard `apply`.
