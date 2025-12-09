# cicd-builder

Automated scaffolding tool to create a **Terraform repository** with a complete **GitHub Actions CI/CD pipeline** on AWS using:

- ✅ **GitHub OIDC** authentication (no long-lived AWS keys)
- ✅ **S3 remote state** with **DynamoDB locking**
- ✅ **Automated CI/CD workflows** (plan on PRs, apply on merge to main)
- ✅ **Branch protection** ready for production use

> **Related docs:** See `GH_OIDC_integration.md` for OIDC details and `cicd_step_by_step_terraform_repo.md` for comprehensive walkthrough.

---

## The Problem

Building CI/CD from scratch is often tedious and time-consuming, especially before you can even begin deploying real infrastructure. CICD-builder automates the entire bootstrap process—provisioning a fully secured, production-grade Terraform CI/CD pipeline in just six commands. It automatically configures IAM, OIDC federation, GitHub workflows, remote state, environment separation, and all required AWS integrations, eliminating hours of repetitive setup and significantly reducing configuration drift.

**Problems Solved:**

1. **Manual Setup Complexity** - Eliminates the tedious, error-prone manual process of setting up Terraform CI/CD infrastructure from scratch

2. **Security Risk of Static AWS Keys** - Replaces long-lived AWS access keys (that can leak) with secure GitHub OIDC authentication using short-lived tokens

3. **Remote State Configuration** - Automates the setup of S3 backend with DynamoDB locking, avoiding state file conflicts and enabling team collaboration

4. **Missing CI/CD Best Practices** - Provides production-ready workflows with automated plan on PRs, automated apply on main branch merges, branch protection, and proper concurrency controls

5. **Scattered Configuration** - Centralizes all setup (AWS infrastructure, GitHub secrets/variables, workflows, branch protection) into 6 simple scripts

6. **Time Investment** - Reduces hours of manual configuration to minutes of automated execution

---

## What This Does

This repository provides **automation scripts** that scaffold a complete Terraform CI/CD pipeline:

1. **Creates a new Terraform repository** with proper structure
2. **Provisions AWS infrastructure** (S3 bucket, DynamoDB table, IAM OIDC provider & role)
3. **Configures GitHub** secrets, variables, and workflows
4. **Sets up branch protection** on main
5. **Installs working CI/CD workflow** (plan on PRs, apply on merging to main)

---

## Prerequisites

### GitHub
- Repository admin access
- GitHub CLI (`gh`) installed and authenticated: `gh auth login`
- Ability to set Actions Secrets/Variables and branch protection

### AWS
- AWS CLI configured with credentials: `aws configure`
- Permissions to create:
  - S3 buckets
  - DynamoDB tables
  - IAM OIDC providers
  - IAM roles and policies

### Local Tools
- `bash` (v4+)
- `git`
- `aws` CLI
- `gh` CLI

---

## Quick Start (6 Steps)

### Step 1: Configure Variables

Edit **`scripts/0-variables.sh`** with your environment details:

```bash
#!/bin/bash
OWNER="your-github-org"           # GitHub owner (org or username)
REPO="your-terraform-repo"        # Repository name to create
AWS_ACCOUNT_ID="123456789012"     # Your AWS account ID
AWS_REGION="us-west-2"            # AWS region

# Backend configuration (customizable)
TF_BACKEND_KEY="terraform.tfstate"
TF_BACKEND_DDB_TABLE="${REPO}-tf-locks"
TF_BACKEND_BUCKET="${REPO}-tfstate-${AWS_ACCOUNT_ID}-${AWS_REGION}"
```

**Note:** S3 bucket names are automatically converted to lowercase.

---

### Step 2: Create Repository Structure

```bash
bash scripts/1-repo_structure.sh
```

**What it creates:**
- Private GitHub repository
- Terraform file structure (main.tf, providers.tf, variables.tf, versions.tf)
- Example VPC configuration
- GitHub Actions workflow directories
- Proper .gitignore

---

### Step 3: Bootstrap AWS Infrastructure

```bash
bash scripts/2-bootstrap_tf_aws.sh
```

⚠️ **Important:** Use `bash`, not `sh`

**What it provisions:**
1. S3 bucket (versioned, encrypted, public access blocked)
2. DynamoDB table for state locking
3. GitHub OIDC provider in IAM
4. IAM role with trust policy for your repository
5. IAM permissions for Terraform backend access

**Trust Policy Pattern:**
```json
"StringLike": {
  "token.actions.githubusercontent.com:sub": [
    "repo:{OWNER}/{REPO}:ref:refs/heads/*",
    "repo:{OWNER}/{REPO}:pull_request"
  ]
}
```

---

### Step 4: Configure GitHub Secrets & Variables

```bash
bash scripts/3-set_gh_variables.sh
```

**Sets Repository Variables:**
- OWNER, REPO, AWS_ACCOUNT_ID, AWS_REGION
- TF_BACKEND_BUCKET, TF_BACKEND_KEY, TF_BACKEND_DDB_TABLE

**Sets Repository Secrets:**
- AWS_ROLE_ARN
- OIDC_PROVIDER_ARN

---

### Step 5: Install CI/CD Workflows

```bash
bash scripts/4-workflow_ci.sh
```

**Creates workflow in generated repository:**
- `terraform-ci.yml` - Plan on feature branches & PRs, apply on merging to main

---

### Step 6: Protect Main Branch

```bash
bash scripts/5-protect_main.sh
```

**Applies rules:**
- Require PR before merging
- Require 1 approval
- Require Terraform CI status check to pass
- Require branches to be up to date
- Require linear history
- Block force pushes and deletions

---

## Developer Workflow

```bash
# 1. Create feature branch
git checkout -b feature/add-infrastructure

# 2. Make changes
vim main.tf

# 3. Format code
terraform fmt

# 4. Commit and push
git add .
git commit -m "feat: add VPC"
git push -u origin feature/add-infrastructure

# 5. Create PR
gh pr create -B main -H feature/add-infrastructure --fill

# 6. CI runs (fmt/validate/plan)
# 7. Get approval
# 8. Merge to main
# 9. Apply runs automatically
```

---

## Repository Structure

```
cicd-builder/
├── scripts/
│   ├── 0-variables.sh            # Configuration (EDIT FIRST)
│   ├── 1-repo_structure.sh       # Creates repo & structure
│   ├── 2-bootstrap_tf_aws.sh     # Provisions AWS resources
│   ├── 3-set_gh_variables.sh     # Configures GitHub
│   ├── 4-workflow_ci.sh          # Installs workflows
│   ├── 5-protect_main.sh         # Branch protection
│   ├── build_tf_baseline.sh      # Helper: generates files
│   └── undo_bootstrap.sh         # Cleanup script
├── .devcontainer/                # Dev container config
├── .gitignore                    # Ignores MyTerraform*/, Containers/
├── README.md                     # This file
├── GH_OIDC_integration.md        # OIDC deep dive
└── cicd_step_by_step_terraform_repo.md  # Full guide

Generated Repository ({REPO}/):
├── .github/workflows/
│   └── terraform-ci.yml          # CI/CD workflow (plan + apply)
├── modules/                      # Terraform modules
├── main.tf                       # Infrastructure resources
├── providers.tf                  # AWS provider
├── variables.tf                  # Variables
├── versions.tf                   # Versions & backend
└── .gitignore                    # Terraform ignores
```

---

## Key Features

### Secure Authentication
- No AWS keys in GitHub - Uses OIDC for temporary credentials
- Fine-grained trust - IAM role limited to specific repo/branches
- Short-lived tokens - AWS credentials expire after ~1 hour
- Auditable - All AWS actions logged in CloudTrail

### Backend Configuration
- Empty backend block in versions.tf (no hardcoded values)
- Configuration via CLI flags in workflows
- Environment variables from GitHub Variables
- Portable across environments

### CI/CD Workflow
- Plan on PRs - Review changes before apply
- Conditional apply - Only runs when pushed to main
- Artifact upload - Plan output saved for review
- Concurrency control - Prevents simultaneous runs

---

## Cleanup

To tear down AWS infrastructure:

```bash
bash scripts/undo_bootstrap.sh
```

**Deletes:**
1. All S3 objects (including versions)
2. S3 bucket
3. DynamoDB table
4. IAM role policy
5. IAM role
6. OIDC provider (optional)

⚠️ **Warning:** This is destructive and cannot be undone.

---

## Troubleshooting

### "Bad substitution" error
**Fix:** Use `bash`, not `sh`: `bash ./scripts/2-bootstrap_tf_aws.sh`

### OIDC authentication fails
**Common issue:** Using `ref:refs/pull/*` instead of `pull_request`  
**Fix:** Re-run `bash scripts/2-bootstrap_tf_aws.sh`

### AWS credentials expired
**Fix:** `aws configure` or `aws sso login`

### Backend initialization fails
**Fix:** Run `bash scripts/3-set_gh_variables.sh`

### Cannot push to main
**Expected:** Branch protection is working  
**Solution:** Create PR instead

---

## Advanced: Terraform Variables

### Declaring Variables
```hcl
variable "vpc_cidr" {
  type        = string
  description = "CIDR block for VPC"
}
```

### Providing Values
In workflow:
```yaml
env:
  TF_VAR_vpc_cidr: ${{ vars.VPC_CIDR }}
```

Set GitHub variable:
```bash
gh variable set VPC_CIDR --body "10.0.0.0/16"
```

---

## Security Best Practices

1. **Minimal IAM permissions** - Start with backend access only
2. **Repository restrictions** - Trust policy limited to your repo
3. **Branch restrictions** - Consider main branch only
4. **GitHub Environments** - Use for production approval gates
5. **Secrets rotation** - OIDC tokens auto-expire
6. **Audit logging** - Review CloudTrail for AWS actions

---

## Additional Resources

- [Terraform S3 Backend](https://www.terraform.io/docs/language/settings/backends/s3.html)
- [GitHub OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [AWS IAM OIDC](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)

---

**Questions?** See `cicd_step_by_step_terraform_repo.md` for detailed explanations.
