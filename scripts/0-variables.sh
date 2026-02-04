#!/bin/bash
# ---- fill these in ----
GH_OWNER="haytemEffectual"
REPO="tf-aws-<projectname>-<clientname>"
AWS_ACCOUNT_ID="000000000000"
AWS_REGION="us-west-2"
# VPC_CIDR="10.0.0.0/24"  # TODO: set VPC_CIDR if the VPC is needed to be created via TF
#
# backend names (you can customize)
TF_BACKEND_S3_KEY="global/terraform.tfstate"
TF_BACKEND_DDB_TABLE="${REPO}-tf-locks"
TF_BACKEND_S3_BUCKET="${REPO}-tfstate-${AWS_ACCOUNT_ID}-${AWS_REGION}"
#
# derived names
OIDC_PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
ROLE_NAME="${REPO}-gha-oidc-role"
ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
