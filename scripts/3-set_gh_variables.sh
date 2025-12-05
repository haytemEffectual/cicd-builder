#!/bin/bash
#### This will set GitHub repo variables and secrets needed for the GitHub Actions workflows
echo "## 3- Setting GitHub repo variables and secrets ##"
. scripts/0-variables.sh
cd "$REPO"
git checkout
gh variable set OWNER --body "$OWNER"
gh variable set REPO --body "$REPO"
gh variable set AWS_ACCOUNT_ID --body "$AWS_ACCOUNT_ID"
gh variable set AWS_REGION --body "$AWS_REGION"

gh variable set TF_BACKEND_BUCKET --body "$TF_BACKEND_BUCKET"
gh variable set TF_BACKEND_KEY --body "$TF_BACKEND_KEY"
gh variable set TF_BACKEND_DDB_TABLE --body "$TF_BACKEND_DDB_TABLE"
gh secret set AWS_ROLE_ARN --body "$ROLE_ARN"
gh secret set OIDC_PROVIDER_ARN --body "$OIDC_PROVIDER_ARN"
cd ..
