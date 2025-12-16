#!/bin/bash
#########################################################################################
## this will Create                                                                    ##
##       1- Create S3 bucket for tfstate   backend                                     ##
##       2- Create DynamoDB table for tfstate locking                                  ##
##       3- (If not already) create the GitHub OIDC provider in IAM                    ##
##       4- Create an IAM role assumed by GitHub Actions via OIDC                      ##
##       5- Attach minimal permissions for Terraform state + your infra (start narrow) ##
#########################################################################################
set -e

if ! gh repo view "$GH_OWNER/$REPO" &>/dev/null; then
    echo "❌ Repository $GH_OWNER/$REPO does not exist!"
    echo "Please run script 1-repo_structure.sh first to create the repository."
    read -p "Press [Enter] key to continue..."
    exit 0
fi
TF_BACKEND_S3_BUCKET="${TF_BACKEND_S3_BUCKET,,}"
echo "## 2- TF bootstrapping: Creating S3 bucket && DynamoDB table ##"
echo ">>>>>..... Creating S3 bucket (if not exists)..."
aws s3api create-bucket \
  --bucket "$TF_BACKEND_S3_BUCKET" \
  --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION" \
  > /dev/null || true # Ignore error if bucket already exists and /dev/null to suppress output

echo ">>>>>..... Configuring S3 bucket settings..."
aws s3api put-bucket-versioning --bucket "$TF_BACKEND_S3_BUCKET" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$TF_BACKEND_S3_BUCKET" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket "$TF_BACKEND_S3_BUCKET" --public-access-block-configuration '{
  "BlockPublicAcls":true,"IgnorePublicAcls":true,"BlockPublicPolicy":true,"RestrictPublicBuckets":true
}'

#### 2 Create DynamoDB lock table
echo ">>>>>..... Creating DynamoDB table (if not exists)..."
aws dynamodb create-table \
  --table-name "$TF_BACKEND_DDB_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$AWS_REGION" \
  > /dev/null || true
##### 3 (If not already) create the GitHub OIDC provider in IAM
# Safe to re-run if it exists; it will just error out if already present.
echo ">>>>>..... Creating OIDC provider (if not exists)..."
aws iam create-open-id-connect-provider \
  --url "https://token.actions.githubusercontent.com" \
  --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" \
  --client-id-list "sts.amazonaws.com" \
  > /dev/null 2>&1 || true

echo ">>>>>..... Getting the OIDC provider ARN ..."
# Construct the exact ARN to ensure we get the right provider
export OIDC_PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

# Verify it exists
if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" > /dev/null 2>&1; then
  echo "ERROR: OIDC provider not found. ARN: $OIDC_PROVIDER_ARN"
  exit 1
fi
echo "OIDC Provider verified: $OIDC_PROVIDER_ARN"

echo "##..... Creating IAM role assumed by GitHub Actions via OIDC..."
# under this line comment should be placed under the line "StringLike" in below policy doc 
# limit to this repo, any branch (refs/heads/*) AND PRs (refs/pull/*)
echo ">>>>>..... Creating IAM role id trust policy..."
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Federated": "${OIDC_PROVIDER_ARN}" },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:${GH_OWNER}/${REPO}:ref:refs/heads/*",
            "repo:${GH_OWNER}/${REPO}:pull_request"
          ]
        }
      }
    }
  ]
}
EOF

echo ">>>>>..... Creating IAM role (if not exists)..."
aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document file://trust-policy.json \
  > /dev/null 2>&1 || true

# Export the role ARN
export ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
echo "IAM Role ARN: $ROLE_ARN"

echo "     ..... Attaching minimal permissions for Terraform state + infra..."
cat > permissions-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    { "Sid": "BackendStateAccess",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::${TF_BACKEND_S3_BUCKET}",
        "arn:aws:s3:::${TF_BACKEND_S3_BUCKET}/*"
      ]
    },
    { "Sid": "DDBLocking",
      "Effect": "Allow",
        "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:DeleteItem",
        "dynamodb:UpdateItem"
        ],
      "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${TF_BACKEND_DDB_TABLE}"
    }
  ]
}
EOF

echo "     ...... Attaching inline policy to IAM role..."
aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "${REPO}-inline-terraform" \
  --policy-document file://permissions-policy.json \
  > /dev/null || true

echo "cleaning up the temporary permisson and trust policy files..."
rm -f trust-policy.json permissions-policy.json

echo ">>>>>>>>>> Bootstrap complete !!! . . . >>>>>>>>>>"
read -p "Press [Enter] key to continue..."