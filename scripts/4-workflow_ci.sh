#!/bin/bash
################################################################################################
## 4- This will create a GitHub Actions workflow file for Terraform CI                        ## 
##    1- for PRs and feature branches plan only:   github/workflows/terraform-ci.yml          ##
##    2- for main branch apply only:               github/workflows/terraform-apply.yml       ##
################################################################################################
set -e
. scripts/0-variables.sh
cd "$REPO"
echo "##..... 4-Creating GitHub Actions workflow files..."
echo "#####  - .github/workflows/terraform-ci.yml"
cat > .github/workflows/terraform-ci.yml <<'CI'
name: terraform-ci
on:
  push:
    branches: [main]   # pushes to main at the merge of PRs
  pull_request:
    branches: [main]          # PRs to main

permissions:
  contents: read
  id-token: write   # needed for OIDC
  pull-requests: write  # to post summary/comments (optional)

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
  # TF_VAR_vpc_cidr: ${{ vars.VPC_CIDR }}

jobs:
  Terraform:
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
            -backend-config="dynamodb_table=${TF_BACKEND_DDB_TABLE}"\
            -backend-config="encrypt=true"

      - name: Format Check
        run: terraform fmt -check -diff

      - name: Validate
        run: terraform validate

      - name: Trivy - vulnerability scanner for IaC
        uses: aquasecurity/trivy-action@0.33.1
        with:
          scan-type: config
          exit-code: 1
          severity: CRITICAL,HIGH

      - name: Terraform Plan
        run: terraform plan -input=false -out=plan.tfplan

      - name: Saving Plan as Artifact
        run: terraform show -no-color plan.tfplan > plan.txt

      - name: Upload Plan Artifact
        uses: actions/upload-artifact@v4
        with:
          name: plan
          path: plan.txt

      - name: TF Apply
        run: terraform apply plan.tfplan -no-color 
        if: github.ref == 'refs/heads/main'
CI

cd ..