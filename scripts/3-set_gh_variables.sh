#!/bin/bash
#### This will set GitHub repo variables and secrets needed for the GitHub Actions workflows
if ! gh repo view "$GH_OWNER/$REPO" &>/dev/null; then
    echo "❌ Repository $GH_OWNER/$REPO does not exist!"
    echo "Please run script 1-repo_structure.sh first to create the repository."
    read -p "Press [Enter] key to continue..."
    exit 0
fi

# Validate required variables are set
required_vars=("GH_OWNER" "REPO" "AWS_ACCOUNT_ID" "AWS_REGION" "TF_BACKEND_S3_BUCKET" "TF_BACKEND_S3_KEY" "TF_BACKEND_DDB_TABLE" "ROLE_ARN")
for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        echo "❌ Error: $var is not set!"
        echo "Please ensure all environment variables are set before running this script."
        exit 1
    fi
done
echo "┌────────────────────────────────────────────────────────┐"
echo "│  3. Setting GitHub repo variables and secrets          │"
echo "└────────────────────────────────────────────────────────┘"

cd "$REPO"
git checkout main
gh variable set GH_OWNER --body "$GH_OWNER"
gh variable set REPO --body "$REPO"
gh variable set AWS_ACCOUNT_ID --body "$AWS_ACCOUNT_ID"
gh variable set AWS_REGION --body "$AWS_REGION"
# gh variable set VPC_CIDR --body "$VPC_CIDR"  # TODO: uncomment and set VPC_CIDR if the VPC is needed to be created via TF
gh variable set TF_BACKEND_S3_BUCKET --body "$TF_BACKEND_S3_BUCKET"
gh variable set TF_BACKEND_S3_KEY --body "$TF_BACKEND_S3_KEY"
gh variable set TF_BACKEND_DDB_TABLE --body "$TF_BACKEND_DDB_TABLE"

gh secret set AWS_ROLE_ARN --body "$ROLE_ARN"
gh secret set OIDC_PROVIDER_ARN --body "$OIDC_PROVIDER_ARN"
cd ..
echo "########## GitHub variables and secrets set !!! . . . ##########"
read -p "Press [Enter] key to continue..."