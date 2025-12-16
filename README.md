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
- Wire up GitHub repo secrets/vars and drop working workflow YAMLs

---

## Quick Start (5 Steps)

> Run these from the repo root. Review each script before executing in your environment.

### 1) Fill variables
Edit **`scripts/0-variables.sh`** with your values (region, repo, AWS account, bucket names, etc.).

```bash
# Example fields you’ll typically set:
GH_OWNER="your-org-or-user"
REPO="your-repo"
AWS_ACCOUNT_ID="123456789012"
AWS_REGION="us-west-2"
TF_BACKEND_S3_BUCKET="your-tfstate-bucket-name"
TF_LOCK_TABLE="terraform-locks"     # optional; empty to skip
OIDC_ROLE_NAME="github-oidc-terraform"
```

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

---

### 4) Set GitHub Variables & Secrets
Run **`scripts/3-variables.sh`** to wire your repo’s **Actions → Secrets/Variables**:

- **Secrets**
  - `AWS_ROLE_ARN` → *the IAM Role ARN created in Step 3*
- **Variables**
  - `AWS_REGION` → e.g., `us-west-2`
  - `TF_BACKEND_S3_BUCKET` → your S3 bucket
  - `TF_BACKEND_S3_KEY` → backend key (e.g., `global/s3/terraform.tfstate`)
  - `TF_BACKEND_DDB_TABLE` → your lock table (or leave empty if unused)

```bash
bash scripts/3-variables.sh
```

---

### 5) Install the CI/CD workflows

Run **`scripts/4-workflow.sh`** to lay down two workflows under `.github/workflows/`:

- **`terraform-ci.yml`** → Runs on feature branches and PRs into `main`  
- **`terraform-apply.yml`** → Runs only when changes are merged to `main`

```text
.github/workflows/
 ├─ terraform-ci.yml
 └─ terraform-apply.yml
```

---

#### `terraform-ci.yml` (feature branches & PRs)

```yaml
name: terraform-ci
on:
  push:
    branches-ignore: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read
  id-token: write
  pull-requests: write

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

env:
  TF_IN_AUTOMATION: "true"
  AWS_REGION: ${{ vars.AWS_REGION }}
  TF_BACKEND_S3_BUCKET: ${{ vars.TF_BACKEND_S3_BUCKET }}
  TF_BACKEND_S3_KEY: ${{ vars.TF_BACKEND_S3_KEY }}
  TF_BACKEND_DDB_TABLE: ${{ vars.TF_BACKEND_DDB_TABLE }}
  AWS_ROLE_ARN: ${{ secrets.AWS_ROLE_ARN }}

jobs:
  terraform-ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ env.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_wrapper: false

      - name: Terraform Init (S3 backend)
        run: |
          terraform init             -backend-config="bucket=${TF_BACKEND_S3_BUCKET}"             -backend-config="key=${TF_BACKEND_S3_KEY}"             -backend-config="region=${AWS_REGION}"             -backend-config="dynamodb_table=${TF_BACKEND_DDB_TABLE}"

      - name: Format Check
        run: terraform fmt -check -diff

      - name: Validate
        run: terraform validate

      - name: Plan
        run: terraform plan -input=false -out=plan.tfplan

      - name: Show Plan (for PR readability)
        if: github.event_name == 'pull_request'
        run: terraform show -no-color plan.tfplan | tee plan.txt

      - name: Upload Plan Artifact
        uses: actions/upload-artifact@v4
        with:
          name: plan
          path: plan.txt
```

---

#### `terraform-apply.yml` (main branch only)

```yaml
name: terraform-apply
on:
  push:
    branches: [main]

permissions:
  contents: read
  id-token: write

concurrency:
  group: ${{ github.workflow }}-main
  cancel-in-progress: false

env:
  TF_IN_AUTOMATION: "true"
  AWS_REGION: ${{ vars.AWS_REGION }}
  TF_BACKEND_S3_BUCKET: ${{ vars.TF_BACKEND_S3_BUCKET }}
  TF_BACKEND_S3_KEY: ${{ vars.TF_BACKEND_S3_KEY }}
  TF_BACKEND_DDB_TABLE: ${{ vars.TF_BACKEND_DDB_TABLE }}
  AWS_ROLE_ARN: ${{ secrets.AWS_ROLE_ARN }}

jobs:
  apply:
    runs-on: ubuntu-latest
    environment: production

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ env.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_wrapper: false

      - name: Terraform Init (S3 backend)
        run: |
          terraform init             -backend-config="bucket=${TF_BACKEND_S3_BUCKET}"             -backend-config="key=${TF_BACKEND_S3_KEY}"             -backend-config="region=${AWS_REGION}"             -backend-config="dynamodb_table=${TF_BACKEND_DDB_TABLE}"

      - name: Terraform Apply
        run: terraform apply -input=false -auto-approve
```

---

## After the 5 Steps

1. **Protect `main`**: Require PR reviews and passing checks before merging.  
2. **Create a PR** → `terraform-ci.yml` runs `fmt/validate/plan` and uploads plan artifact.  
3. **Merge to main** → `terraform-apply.yml` runs `apply` (with optional environment approvals).

---

## File Map

- `scripts/0-variables.sh` — Fill in your org/repo/AWS/account values
- `scripts/1-repo_structure.sh` — Create & push Terraform folder structure
- `scripts/2-bootstrap_tf.sh` — Provision backend + OIDC provider/role
- `scripts/3-variables.sh` — Set GitHub Variables & Secrets
- `scripts/4-workflow.sh` — Install CI/CD workflows
- `.github/workflows/terraform-ci.yml` — CI workflow for PRs/branches
- `.github/workflows/terraform-apply.yml` — Apply workflow for main
- `GH_OIDC_rundown.md` — OIDC trust/role details
- `cicd_step_by_step_terraform_repo.md` — Full walkthrough

---

## Notes & Safety

- Limit IAM role permissions to only what Terraform needs.  
- Restrict OIDC trust policy to your repo + branch.  
- Use **GitHub Environments** with required reviewers for production applies.
