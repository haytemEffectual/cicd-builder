```
██████╗ ██╗██████╗ ███████╗ ██████╗██████╗  █████╗ ███████╗████████╗███████╗██████╗ 
██╔══██╗██║██╔══██╗██╔════╝██╔════╝██╔══██╗██╔══██╗██╔════╝╚══██╔══╝██╔════╝██╔══██╗
██████╔╝██║██████╔╝█████╗  ██║     ██████╔╝███████║█████╗     ██║   █████╗  ██████╔╝
██╔═══╝ ██║██╔═══╝ ██╔══╝  ██║     ██╔══██╗██╔══██║██╔══╝     ██║   ██╔══╝  ██╔══██╗
██║     ██║██║     ███████╗╚██████╗██║  ██║██║  ██║██║        ██║   ███████╗██║  ██║
╚═╝     ╚═╝╚═╝     ╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝        ╚═╝   ╚══════╝╚═╝  ╚═╝
```

# PIPECRAFTER

**Automate Terraform CI/CD pipelines on AWS with GitHub Actions using secure OIDC authentication**

PipeCrafter is a Python-based automation tool that scaffolds complete **Terraform repositories** with production-ready **GitHub Actions CI/CD pipelines**, **AWS S3 backend**, **DynamoDB state locking**, and **GitHub OIDC authentication**—eliminating the need for long-lived AWS credentials.

---

## ✨ Features

- 🔐 **Secure OIDC Authentication** - No static AWS keys, uses GitHub OIDC for temporary credentials
- 🏗️ **Complete Infrastructure Setup** - Automated S3 bucket, DynamoDB table, and IAM role creation
- 🚀 **Production-Ready Workflows** - Pre-configured GitHub Actions for Terraform CI/CD
- 🎯 **Interactive Menu Interface** - User-friendly Python orchestrator for all setup steps
- 🔒 **Branch Protection** - Automated protection rules for main branch
- 📦 **Terraform Best Practices** - Remote state, state locking, and version constraints
- 🛡️ **Security Scanning** - Integrated Trivy vulnerability scanner for IaC
- 🔄 **Easy Cleanup** - One-command teardown of all AWS resources

---

## 🎯 What Gets Created

### AWS Infrastructure
- **S3 Bucket** for Terraform remote state (with versioning, encryption, and public access blocked)
- **DynamoDB Table** for state locking and consistency
- **IAM OIDC Provider** for GitHub Actions authentication
- **IAM Role** with trust policy limiting access to specific repository and branches
- **IAM Permissions** scoped to backend access (S3 + DynamoDB)

### GitHub Repository
- **Terraform File Structure** (`main.tf`, `providers.tf`, `versions.tf`, `variables.tf`)
- **GitHub Actions Workflow** (`terraform-ci.yml`) with plan and apply stages
- **Repository Variables** (AWS_REGION, backend configuration, etc.)
- **Repository Secrets** (AWS_ROLE_ARN, OIDC_PROVIDER_ARN)
- **Branch Protection Rules** (optional, requires GitHub Plus or public repo)

---

## 📋 Prerequisites

### Required Tools
- **Python 3.x** (with `subprocess`, `os`, `re` modules)
- **AWS CLI** configured with credentials for target account
- **GitHub CLI (`gh`)** authenticated to your GitHub account
- **Git** for repository operations
- **Bash shell** for script execution

### AWS Permissions Required
Your AWS user/role must have permissions to create:
- S3 buckets and configure bucket settings
- DynamoDB tables
- IAM OIDC providers
- IAM roles and policies

### GitHub Access Required
- Repository creation permissions in target organization/account
- Admin access to set Actions secrets and variables
- Ability to configure branch protection rules (optional)

---

## 🚀 Quick Start

### 1. Configure Variables

Edit [scripts/0-variables.sh](scripts/0-variables.sh) with your specific values:

```bash
GH_OWNER="your-github-username"        # GitHub organization or username
REPO="your-repo-name"                  # Repository name to create
AWS_ACCOUNT_ID="123456789012"          # Your AWS account ID
AWS_REGION="us-west-2"                 # AWS region for resources
TF_BACKEND_S3_KEY="global/terraform.tfstate"  # S3 key for state file
```

> **Note**: S3 bucket name and DynamoDB table name are automatically generated based on your REPO, AWS_ACCOUNT_ID, and AWS_REGION values to ensure uniqueness.

### 2. Run PipeCrafter

Execute the main Python orchestrator:

```bash
python3 PCraft.py
```

You'll see an interactive menu with the following options:

```
1. Building basic repo structure
2. Setting TF backend structure (S3 + DDB), IAM permissions, and OIDC role in AWS
3. Configuring GitHub variables and secrets
4. Creating cicd gh actions workflows
5. Configuring main branch protection rules
6. Undo step 2, and destroy TF backend (S3 + DDB) and IAM role in AWS
7. All of the above
8. Exit
```

### 3. Choose Setup Option

- **Option 7 (Recommended)**: Run complete automated setup end-to-end
- **Individual Options**: Execute specific steps if you need granular control
- **Option 6**: Cleanup/teardown all AWS resources created in step 2

---

## 📂 Project Structure

```
.
├── PCraft.py                          # Main Python orchestrator
├── scripts/
│   ├── 0-variables.sh                 # Configuration variables
│   ├── 1-repo_structure.sh            # Create GitHub repo and Terraform structure
│   ├── 2-bootstrap_tf_aws.sh          # Bootstrap AWS resources (S3, DynamoDB, IAM)
│   ├── 3-set_gh_variables.sh          # Configure GitHub secrets and variables
│   ├── 4-workflow_ci.sh               # Generate GitHub Actions workflows
│   ├── 5-protect_main.sh              # Apply branch protection rules
│   ├── build_tf_baseline.sh           # Create baseline Terraform files
│   └── undo_bootstrap.sh              # Cleanup AWS resources
├── README.md                          # This file
├── GH_OIDC_integration.md             # Deep dive on OIDC integration
└── cicd_step_by_step_terraform_repo.md # Step-by-step walkthrough
```

---

## 🔧 Detailed Workflow Steps

### Step 1: Building Repo Structure

**Script**: [scripts/1-repo_structure.sh](scripts/1-repo_structure.sh)

Creates the GitHub repository and initializes Terraform file structure:

- ✅ Creates private GitHub repository with description
- ✅ Checks if repository already exists (prevents duplicates)
- ✅ Clones repository locally
- ✅ Creates `.gitignore` with Terraform-specific entries
- ✅ Generates Terraform files: `versions.tf`, `providers.tf`, `main.tf`, `variables.tf`
- ✅ Creates `modules/` and `.github/workflows/` directories
- ✅ Commits and pushes initial structure to main branch

**Files Created**:
```
your-repo/
├── .gitignore
├── main.tf
├── providers.tf
├── variables.tf
├── versions.tf
├── modules/
└── .github/workflows/
```

---

### Step 2: Bootstrap AWS Infrastructure

**Script**: [scripts/2-bootstrap_tf_aws.sh](scripts/2-bootstrap_tf_aws.sh)

Sets up AWS resources for Terraform backend and GitHub Actions authentication:

#### S3 Bucket Configuration
- Creates S3 bucket (lowercase enforced per AWS requirements)
- Enables versioning for state file history
- Configures AES256 server-side encryption
- Blocks all public access

#### DynamoDB Table
- Creates table with `LockID` as partition key
- Configured for PAY_PER_REQUEST billing
- Enables Terraform state locking

#### IAM OIDC Provider
- Creates OIDC provider for `token.actions.githubusercontent.com`
- Uses official GitHub thumbprint: `6938fd4d98bab03faadb97b34396831e3780aea1`
- Configures `sts.amazonaws.com` as client ID

#### IAM Role with Trust Policy
- Creates role assumable by GitHub Actions via OIDC
- Trust policy restricts access to:
  - Specific repository: `repo:${GH_OWNER}/${REPO}:ref:refs/heads/*`
  - Pull requests: `repo:${GH_OWNER}/${REPO}:pull_request`
- Attached permissions policy grants:
  - S3 access: `ListBucket`, `GetObject`, `PutObject`, `DeleteObject`
  - DynamoDB access: `PutItem`, `GetItem`, `DeleteItem`, `UpdateItem`

**Resources Created**:
- S3 Bucket: `${REPO}-tfstate-${AWS_ACCOUNT_ID}-${AWS_REGION}` (lowercase)
- DynamoDB Table: `${REPO}-tf-locks`
- IAM OIDC Provider: `arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com`
- IAM Role: `${REPO}-gha-oidc-role`

---

### Step 3: Configure GitHub Secrets and Variables

**Script**: [scripts/3-set_gh_variables.sh](scripts/3-set_gh_variables.sh)

Configures GitHub repository with all necessary variables and secrets for workflows:

**Repository Variables** (accessible via `vars.VARIABLE_NAME`):
- `GH_OWNER` - GitHub organization/username
- `REPO` - Repository name
- `AWS_ACCOUNT_ID` - AWS account ID
- `AWS_REGION` - AWS region (e.g., us-west-2)
- `TF_BACKEND_S3_BUCKET` - S3 bucket name for state
- `TF_BACKEND_S3_KEY` - S3 key path for state file
- `TF_BACKEND_DDB_TABLE` - DynamoDB table for locking

**Repository Secrets** (accessible via `secrets.SECRET_NAME`):
- `AWS_ROLE_ARN` - IAM role ARN for OIDC authentication
- `OIDC_PROVIDER_ARN` - OIDC provider ARN

> **Note**: Validates all required variables are set before proceeding

---

### Step 4: Create GitHub Actions Workflow

**Script**: [scripts/4-workflow_ci.sh](scripts/4-workflow_ci.sh)

Generates a production-ready GitHub Actions workflow file at `.github/workflows/terraform-ci.yml`:

**Workflow Features**:
- **Triggers**: 
  - Push to `main` branch (for apply after PR merge)
  - Pull requests to `main` branch (for plan validation)
- **OIDC Authentication**: Uses `aws-actions/configure-aws-credentials@v4` with `id-token: write` permission
- **Terraform Workflow**:
  1. Checkout code
  2. Configure AWS credentials via OIDC
  3. Setup Terraform (using `hashicorp/setup-terraform@v3`)
  4. Initialize with S3 backend configuration
  5. Format check (`terraform fmt -check -diff`)
  6. Validate configuration
  7. Run Trivy security scanner (fails on CRITICAL/HIGH vulnerabilities)
  8. Generate plan (`terraform plan -out=plan.tfplan`)
  9. Upload plan as artifact
  10. Apply changes (only on main branch pushes)

**Concurrency Control**:
- Prevents concurrent workflow runs on same branch
- Cancels in-progress runs when new commits pushed

**Backend Configuration**:
```bash
terraform init \
  -backend-config="bucket=${TF_BACKEND_BUCKET}" \
  -backend-config="key=${TF_BACKEND_KEY}" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="dynamodb_table=${TF_BACKEND_DDB_TABLE}" \
  -backend-config="encrypt=true"
```

---

### Step 5: Branch Protection Rules

**Script**: [scripts/5-protect_main.sh](scripts/5-protect_main.sh)

Applies GitHub branch protection rules to the main branch:

**Protection Rules Applied**:
- ✅ Require pull request before merging
- ✅ Require 1 approving review
- ✅ Dismiss stale reviews on new commits
- ✅ Require status checks to pass (specifically `Terraform` job)
- ✅ Require branches to be up to date before merging
- ✅ Require linear history (no merge commits)
- ✅ Enforce rules for administrators
- ❌ Block force pushes
- ❌ Block branch deletions

> **Important**: This step requires either GitHub Plus subscription or a public repository. Free private repositories have limited branch protection features.

---

### Step 6: Cleanup (Undo Bootstrap)

**Script**: [scripts/undo_bootstrap.sh](scripts/undo_bootstrap.sh)

Tears down all AWS resources created in Step 2:

**Cleanup Actions**:
1. Deletes all objects from S3 bucket (recursive)
2. Deletes S3 bucket
3. Deletes DynamoDB table
4. Deletes IAM role inline policy
5. Deletes IAM role
6. Deletes IAM OIDC provider

> **Note**: This does not delete the GitHub repository or remove variables/secrets. Repository must be deleted manually if desired.

---

## 🔐 Security Best Practices

### OIDC Authentication Benefits
- **No Long-Lived Credentials**: GitHub Actions receives temporary credentials valid for workflow duration only
- **Scoped Access**: Trust policy restricts which repositories and branches can assume the role
- **Audit Trail**: CloudTrail logs all AssumeRoleWithWebIdentity calls with GitHub context

### IAM Permissions
- **Principle of Least Privilege**: Role only has permissions for S3/DynamoDB backend operations
- **Resource-Level Restrictions**: Permissions scoped to specific bucket and table ARNs
- **No Wildcard Access**: No `*` resources in permission policies

### Recommendations
1. **Review Trust Policy**: Ensure `StringLike` condition matches only your repository
2. **Enable CloudTrail**: Monitor all API calls made by the GitHub Actions role
3. **Rotate Secrets Regularly**: Although OIDC eliminates static keys, review IAM role permissions periodically
4. **Use Branch Protection**: Require reviews before merging to main
5. **Enable Security Scanning**: Trivy scanner catches vulnerabilities before apply

---

## 🐛 Troubleshooting

### Common Issues

#### Repository Already Exists
**Error**: `Repository $GH_OWNER/$REPO already exists`  
**Solution**: Script will skip creation. Manually delete repository from GitHub if you want to recreate it.

#### S3 Bucket Name Invalid
**Error**: `InvalidBucketName: The specified bucket is not valid`  
**Solution**: PipeCrafter automatically converts bucket names to lowercase. Ensure no special characters in REPO or AWS_ACCOUNT_ID.

#### OIDC Authentication Fails
**Error**: `Error: Not authorized to perform sts:AssumeRoleWithWebIdentity`  
**Solution**: 
- Verify trust policy in IAM role includes correct repository path
- Ensure `GH_OWNER` matches exactly (case-sensitive)
- Check workflow has `id-token: write` permission

#### Branch Protection Fails
**Error**: `404 Not Found` when applying branch protection  
**Solution**: Branch protection requires GitHub Plus or public repository. Free private repos have limited features.

#### Terraform Backend Initialization Fails
**Error**: `Error: Failed to get existing workspaces: AccessDenied`  
**Solution**:
- Verify S3 bucket exists and is in correct region
- Confirm IAM role has permissions to bucket and DynamoDB table
- Check backend configuration uses correct variable names (`TF_BACKEND_BUCKET` vs `TF_BACKEND_S3_BUCKET`)

---

## 📚 Additional Documentation

- [GH_OIDC_integration.md](GH_OIDC_integration.md) - Deep dive into GitHub OIDC authentication with AWS
- [cicd_step_by_step_terraform_repo.md](cicd_step_by_step_terraform_repo.md) - Manual step-by-step walkthrough

---

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

## 📝 License

This project is provided as-is for educational and automation purposes.

---

## 🙋 Support

For issues, questions, or contributions, please open an issue on GitHub.
