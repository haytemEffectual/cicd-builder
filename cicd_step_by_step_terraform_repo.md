# Terraform CI/CD on GitHub with S3 Backend (Step-by-Step Guide)

A practical, automated walkthrough for setting up a Terraform repository on GitHub with:

- **S3 backend** with **DynamoDB** for state locking
- **GitHub OIDC** authentication to AWS (no long-lived AWS keys)
- **CI (fmt/validate/plan)** on feature branches & PRs
- **Apply** only after merging to **`main`**
- **Branch protection** preventing direct pushes to `main`

---

## Repository Overview

This repository contains **automated scripts** to scaffold a complete Terraform CI/CD pipeline. The scripts handle:

1. Repository structure creation
2. AWS infrastructure bootstrapping (S3, DynamoDB, IAM OIDC)
3. GitHub secrets/variables configuration
4. CI/CD workflow installation
5. Branch protection setup

---

## Prerequisites

- **AWS account** with permissions to create S3 buckets, DynamoDB tables, and IAM roles/policies
- **AWS CLI** configured with appropriate credentials
- **GitHub account** with repository admin access
- **GitHub CLI** (`gh`) installed and authenticated (`gh auth login`)
- **Terraform** installed locally (optional, for testing)

---

## Quick Start (Automated Setup)

### Step 1: Configure Variables

Edit **`scripts/0-variables.sh`** with your values. The bucket name will be automatically converted to lowercase.

### Step 2: Create Repository Structure

Run **`scripts/1-repo_structure.sh`**

### Step 3: Bootstrap AWS Infrastructure

Run **`scripts/2-bootstrap_tf_aws.sh`** (use `bash`, not `sh`)

### Step 4: Set GitHub Variables & Secrets

Run **`scripts/3-set_gh_variables.sh`**

### Step 5: Install CI/CD Workflows

Run **`scripts/4-workflow_ci.sh`**

### Step 6: Protect Main Branch

Run **`scripts/5-protect_main.sh`**

---

## Understanding GitHub OIDC

### Trust Policy Patterns

The IAM role trust policy uses these patterns:

- `repo:{OWNER}/{REPO}:ref:refs/heads/*` - Matches all branch pushes
- `repo:{OWNER}/{REPO}:pull_request` - Matches pull request events

**Important:** Use `pull_request` (literal), NOT `ref:refs/pull/*`

---

## Cleanup

To tear down AWS resources: `bash scripts/undo_bootstrap.sh`

