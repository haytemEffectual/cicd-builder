#!/bin/bash
##### 1 Create S3 bucket for tfstate
. scripts/0-variables.sh
TF_BACKEND_BUCKET="${TF_BACKEND_BUCKET,,}"
echo "Creating S3 bucket (if not exists)..."
aws s3api create-bucket \
  --bucket "$TF_BACKEND_BUCKET" \
  --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION" \
  > /dev/null || true

echo "Configuring S3 bucket settings..."
aws s3api put-bucket-versioning --bucket "$TF_BACKEND_BUCKET" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$TF_BACKEND_BUCKET" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket "$TF_BACKEND_BUCKET" --public-access-block-configuration '{
  "BlockPublicAcls":true,"IgnorePublicAcls":true,"BlockPublicPolicy":true,"RestrictPublicBuckets":true
}'

#### 2 Create DynamoDB lock table
echo "Creating DynamoDB table (if not exists)..."
aws dynamodb create-table \
  --table-name "$TF_BACKEND_DDB_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$AWS_REGION" \
  > /dev/null || true
##### 3 (If not already) create the GitHub OIDC provider in IAM
# Safe to re-run if it exists; it will just error out if already present.
echo "Creating IAM OIDC provider (if not exists)..."
aws iam create-open-id-connect-provider \
  --url "https://token.actions.githubusercontent.com" \
  --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" \
  --client-id-list "sts.amazonaws.com" \
  > /dev/null || true
##### 4 Create an IAM role assumed by GitHub Actions via OIDC
# under this line comment should be placed under the line "StringLike" in below policy doc 
# limit to this repo, any branch (refs/heads/*) AND PRs (refs/pull/*)
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
            "repo:${OWNER}/${REPO}:ref:refs/heads/*",
            "repo:${OWNER}/${REPO}:ref:refs/pull/*"
          ]
        }
      }
    }
  ]
}
EOF

echo "Creating IAM role (if not exists)..."
aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document file://trust-policy.json \
  > /dev/null || true
##### 5 Attach minimal permissions for Terraform state + your infra (start narrow)
cat > permissions-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    { "Sid": "BackendStateAccess",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket","s3:GetObject","s3:PutObject","s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::${TF_BACKEND_BUCKET}",
        "arn:aws:s3:::${TF_BACKEND_BUCKET}/*"
      ]
    },
    { "Sid": "DDBLocking",
      "Effect": "Allow",
      "Action": ["dynamodb:PutItem","dynamodb:GetItem","dynamodb:DeleteItem","dynamodb:UpdateItem"],
      "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${TF_BACKEND_DDB_TABLE}"
    }
  ]
}
EOF

echo "Attaching inline policy to IAM role..."
aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "${REPO}-inline-terraform" \
  --policy-document file://permissions-policy.json \
  > /dev/null || true

echo "cleaning up the temporary permisson and trust policy files..."
rm -f trust-policy.json permissions-policy.json

echo "Bootstrap complete !!!"