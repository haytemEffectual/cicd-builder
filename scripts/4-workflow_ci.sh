#!/bin/bash
### Create a GitHub Actions workflow file for Terraform CI

if ! gh repo view "$GH_OWNER/$REPO" &>/dev/null; then
    echo "❌ Repository $GH_OWNER/$REPO does not exist!"
    echo "Please run script 1-repo_structure.sh first to create the repository."
    read -p "Press [Enter] key to continue..."
    exit 0
fi
cd "$REPO"
echo "##..... 4-Creating GitHub Actions workflow files..."
echo ">>>>>  - .github/workflows/terraform-ci.yml"
cat > .github/workflows/terraform-ci.yml <<'CI'
name: terraform-ci
on:
  push:
    branches-ignore: [main]   # feature branches
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
          terraform init \
            -backend-config="bucket=${TF_BACKEND_S3_BUCKET}" \
            -backend-config="key=${TF_BACKEND_S3_KEY}" \
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
CI

cd ..
echo "########## GitHub Actions workflow files created !!! . . . ##########"
read -p "Press [Enter] key to continue..."