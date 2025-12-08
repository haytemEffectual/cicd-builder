#!/bin/bash
# ---- fill these in ----
OWNER="haytemEffectual"
REPO="MyTerraformProject"
AWS_ACCOUNT_ID="478530404284"
AWS_REGION="us-west-2"

# backend names (you can customize)
TF_BACKEND_KEY="terraform.tfstate"
TF_BACKEND_DDB_TABLE="${REPO}-tf-locks"
TF_BACKEND_BUCKET="${REPO}-tfstate-${AWS_ACCOUNT_ID}-${AWS_REGION}"
TF_BACKEND_BUCKET="${TF_BACKEND_BUCKET,,}"

# derived names
OIDC_PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
ROLE_NAME="${REPO}-gha-oidc-role"
ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
