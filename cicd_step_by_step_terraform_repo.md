# Beginner’s Guide: Terraform CI/CD on GitHub with S3 Backend (Step‑by‑Step)

A practical, copy‑pasteable walkthrough for first‑timers. You’ll build a Terraform repository on GitHub that:

- Uses an **S3 backend** with **DynamoDB** for state locking.
- Authenticates to AWS via **GitHub OIDC** (no long‑lived AWS keys).
- Runs **CI (fmt/validate/plan)** on feature branches & PRs.
- **Applies** only after merging to **`main`**.
- Enforces **branch protection** so no direct pushes to `main`.

---

## 1) Who this is for & What you’ll build
If you’re new to GitHub Actions and Terraform, this guide explains each step and why it matters. By the end, you’ll have a secure and reproducible Terraform delivery workflow suitable for teams.

---

## 2) Prerequisites
- **AWS account** with permissions to create S3 buckets, DynamoDB tables, and IAM roles/policies.
- **AWS CLI** logged in as an admin or equivalent.
- **GitHub account**; optionally **GitHub CLI** (`gh`) logged in.
- **Terraform** installed locally (for testing) — though CI will also install it.

> Tip: If you’re in an organization, coordinate bucket naming and IAM conventions up front.

---

## 3) Variables you’ll use
Fill these once and reuse in commands:

```bash
OWNER="your-org-or-username"
REPO="tf-s3-ci"
AWS_ACCOUNT_ID="123456789012"
AWS_REGION="us-west-2"

# backend names (customize as needed)
TF_BACKEND_BUCKET="${REPO}-tfstate-${AWS_ACCOUNT_ID}-${AWS_REGION}"
TF_BACKEND_KEY="global/terraform.tfstate"
TF_BACKEND_DDB_TABLE="${REPO}-tf-locks"

# derived names
OIDC_PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
ROLE_NAME="${REPO}-gha-oidc-role"
ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
```

---

## 4) Create the repository and scaffold Terraform
### Option A — GitHub CLI
```bash
gh repo create "$OWNER/$REPO" --private --description "Terraform + S3 backend + OIDC CI/CD" --confirm
git clone "https://github.com/$OWNER/$REPO.git"
cd "$REPO"

mkdir -p .github/workflows modules/.keep

cat > versions.tf <<'TF'
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
  backend "s3" {}
}
TF

cat > providers.tf <<'TF'
variable "aws_region" { type = string, default = "us-west-2" }
provider "aws" { region = var.aws_region }
TF

cat > main.tf <<'TF'
# Example — replace with your real infra later
data "aws_caller_identity" "current" {}
output "account_id" { value = data.aws_caller_identity.current.account_id }
TF

cat > .gitignore <<'GIT'
.terraform/
.terraform.lock.hcl
*.tfstate
*.tfstate.*
crash.log
*.tfplan
GIT

git add .
git commit -m "init: terraform skeleton"
git push -u origin main
```

### Option B — GitHub Web UI
1. Create a new repo (Private recommended). Default branch: **main**.
2. Add files above through the web editor or clone/push from local.

> **Why is `backend "s3" {}` empty?** We pass backend details via CI flags so no environment‑specific identifiers or secrets live in Git. This keeps the repo portable and safer.

---

## 5) Bootstrap AWS once (State + OIDC role)
Run these with admin credentials. They create the S3 backend bucket, DynamoDB lock table, and an IAM role that trusts GitHub OIDC.

```bash
# 5.1 Create versioned, encrypted S3 bucket
aws s3api create-bucket \
  --bucket "$TF_BACKEND_BUCKET" \
  --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION"
aws s3api put-bucket-versioning --bucket "$TF_BACKEND_BUCKET" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$TF_BACKEND_BUCKET" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket "$TF_BACKEND_BUCKET" --public-access-block-configuration '{
  "BlockPublicAcls":true,"IgnorePublicAcls":true,"BlockPublicPolicy":true,"RestrictPublicBuckets":true
}'

# 5.2 Create DynamoDB lock table
aws dynamodb create-table \
  --table-name "$TF_BACKEND_DDB_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

# 5.3 Ensure GitHub OIDC provider exists (idempotent)
aws iam create-open-id-connect-provider \
  --url "https://token.actions.githubusercontent.com" \
  --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" \
  --client-id-list "sts.amazonaws.com" || true

# 5.4 Create IAM role trusted by your repo (any branch + PRs)
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Federated": "${OIDC_PROVIDER_ARN}" },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:${OWNER}/${REPO}:ref:refs/heads/*",
            "repo:${OWNER}/${REPO}:ref:refs/pull/*"
          ]
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document file://trust-policy.json

# 5.5 Attach minimal permissions for Terraform backend
cat > permissions-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    { "Sid": "BackendStateAccess",
      "Effect": "Allow",
      "Action": ["s3:ListBucket","s3:GetObject","s3:PutObject","s3:DeleteObject"],
      "Resource": [
        "arn:aws:s3:::${TF_BACKEND_BUCKET}",
        "arn:aws:s3:::${TF_BACKEND_BUCKET}/*"
      ]
    },
    { "Sid": "DDBLocking",
      "Effect": "Allow",
      "Action": ["dynamodb:PutItem","dynamodb:GetItem","dynamodb:DeleteItem","dynamodb:UpdateItem"],
      "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${TF_BACKEND_DDB_TABLE}"
    }
    # Add infra permissions you actually need (VPC, S3, IAM, etc.)
  ]
}
EOF

aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "${REPO}-inline-terraform" \
  --policy-document file://permissions-policy.json
```

---

## 6) Configure GitHub Variables & Secrets
### GitHub Web UI
- Go to **Settings → Secrets and variables → Actions**.
- **Repository Variables**:
  - `AWS_REGION` = your region (e.g., `us-west-2`)
  - `TF_BACKEND_BUCKET` = your backend bucket
  - `TF_BACKEND_KEY` = e.g., `global/terraform.tfstate`
  - `TF_BACKEND_DDB_TABLE` = your lock table
- **Repository Secrets**:
  - `AWS_ROLE_ARN` = `arn:aws:iam::…:role/${ROLE_NAME}`

### GitHub CLI
```bash
gh variable set AWS_REGION --body "$AWS_REGION"
gh variable set TF_BACKEND_BUCKET --body "$TF_BACKEND_BUCKET"
gh variable set TF_BACKEND_KEY --body "$TF_BACKEND_KEY"
gh variable set TF_BACKEND_DDB_TABLE --body "$TF_BACKEND_DDB_TABLE"
gh secret set AWS_ROLE_ARN --body "$ROLE_ARN"
```

---

## 7) CI workflow — Terraform fmt/validate/plan (PRs & feature branches)
Create `.github/workflows/terraform-ci.yml`:

```yaml
name: terraform-ci
on:
  push:
    branches-ignore: [main]   # feature branches
  pull_request:
    branches: [main]          # PRs to main

permissions:
  contents: read
  id-token: write   # needed for OIDC
  pull-requests: write  # if you later want to comment to PRs

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

env:
  TF_IN_AUTOMATION: "true"
  AWS_REGION: ${{ vars.AWS_REGION }}
  TF_BACKEND_BUCKET: ${{ vars.TF_BACKEND_BUCKET }}
  TF_BACKEND_KEY: ${{ vars.TF_BACKEND_KEY }}
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
          terraform init \
            -backend-config="bucket=${TF_BACKEND_BUCKET}" \
            -backend-config="key=${TF_BACKEND_KEY}" \
            -backend-config="region=${AWS_REGION}" \
            -backend-config="dynamodb_table=${TF_BACKEND_DDB_TABLE}"

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

### What each part does (high level)
- **Triggers**: runs on pushes to feature branches and PRs to `main`.
- **Permissions**: `id-token: write` enables GitHub **OIDC** to AWS; others are least‑privilege.
- **Concurrency**: cancels older runs on the same branch when a new push arrives.
- **Init**: wires Terraform to your S3+DDB backend.
- **Fmt/Validate/Plan**: quick feedback for reviewers; plan is uploaded as an artifact.

> Deep dive available in the conversation notes: we explained every line of this workflow for learners.

---

## 8) Apply workflow — only after merge to `main`
Create `.github/workflows/terraform-apply.yml`:

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
  TF_BACKEND_BUCKET: ${{ vars.TF_BACKEND_BUCKET }}
  TF_BACKEND_KEY: ${{ vars.TF_BACKEND_KEY }}
  TF_BACKEND_DDB_TABLE: ${{ vars.TF_BACKEND_DDB_TABLE }}
  AWS_ROLE_ARN: ${{ secrets.AWS_ROLE_ARN }}

jobs:
  apply:
    runs-on: ubuntu-latest
    environment: production  # optional approvals gate

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
          terraform init \
            -backend-config="bucket=${TF_BACKEND_BUCKET}" \
            -backend-config="key=${TF_BACKEND_KEY}" \
            -backend-config="region=${AWS_REGION}" \
            -backend-config="dynamodb_table=${TF_BACKEND_DDB_TABLE}"

      - name: Terraform Apply
        run: terraform apply -input=false -auto-approve
```

**Outcome:** nothing applies from PRs/feature branches; only merges to `main` run apply.

---

## 9) Protect `main` so only PRs can change it
### GitHub Web UI
1. Go to **Settings → Branches → Add rule**.
2. **Branch name pattern:** `main`.
3. Enable:
   - **Require a pull request before merging** (blocks direct pushes).
   - **Require approvals** (e.g., 1).
   - **Require status checks to pass**; add **`terraform-ci`**.
   - **Require branches to be up to date** (recommended).
   - **Require linear history** (recommended).
   - **Include administrators**.

### GitHub CLI / REST
```bash
cat > protection.json <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["terraform-ci"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "require_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON

gh api -X PUT \
  -H "Accept: application/vnd.github+json" \
  "/repos/$OWNER/$REPO/branches/main/protection" \
  --input protection.json
```

**Result:** no one can push to `main`; merges require passing checks + approval.

---

## 10) Repo Roles & Access
- **Maintainers**: `admin` (or `maintain`).
- **Developers**: `write` (push to feature branches; `main` is blocked by protection).
- **Viewers/QA**: `triage` or `read`.

CLI examples:
```bash
ORG="your-org"; TEAM_DEVS="devs"; TEAM_MAINT="maintainers"
gh api -X PUT "/orgs/$ORG/teams/$TEAM_DEVS/repos/$ORG/$REPO" -f permission=push
gh api -X PUT "/orgs/$ORG/teams/$TEAM_MAINT/repos/$ORG/$REPO" -f permission=admin
```

---

## 11) Day‑to‑Day Developer Flow
```bash
git checkout -b feature/my-change
# edit .tf files…
terraform fmt
git add -A
git commit -m "feat: my change"
git push -u origin feature/my-change

# open PR targeting main
gh pr create -B main -H feature/my-change --fill
# Wait for terraform-ci to pass; get approval; merge (squash recommended).
# terraform-apply will run on main and apply the changes.
```

---

## 12) Security Notes: Why `id-token: write`?
`id-token: write` lets GitHub mint a short‑lived **OIDC token** so AWS can issue temporary credentials via **AssumeRoleWithWebIdentity**. It does **not** grant repo write access; it enables secure, keyless cloud auth. Limit trust in the IAM role to this repo/branches/PRs as shown.

---

## 13) Multi‑Environment Pattern (Optional)
- Use separate state keys or buckets per environment, e.g.:
  - `envs/dev/terraform.tfstate`, `envs/prod/terraform.tfstate`.
- Create **one IAM role per environment** and store role ARNs as environment secrets with **GitHub Environments** (Dev/Prod) to gate approvals and access.
- Duplicate workflows or use a matrix/strategy to target directories/envs.

---

## 14) Troubleshooting
- **`AccessDenied` on S3/DDB**: verify the IAM inline policy includes the bucket/table ARNs and the job assumed the right role.
- **Backend init fails**: ensure bucket exists in the same region you pass to Terraform; check the DDB table name and region.
- **OIDC trust mismatch**: confirm `Condition` in the trust policy matches your `OWNER/REPO` and ref patterns (heads/* and pull/*).
- **Status check not required**: make sure you added **`terraform-ci`** as a required check in branch protection.

---

## 15) Full Files (Copy‑Paste)
### `.github/workflows/terraform-ci.yml`
(See Section 7 — same content.)

### `.github/workflows/terraform-apply.yml`
(See Section 8 — same content.)

### `versions.tf`, `providers.tf`, `main.tf`, `.gitignore`
(See Section 4 — same content.)

---

**You’re done!** You now have a secure, beginner‑friendly Terraform CI/CD pipeline that enforces PR‑only changes to `main` and uses keyless AWS auth via OIDC.

