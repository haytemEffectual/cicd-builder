#!/bin/bash
set -e

. scripts/0-variables.sh
TF_BACKEND_BUCKET="${TF_BACKEND_BUCKET,,}"

echo -e "\n 1- Deleting all objects from S3 bucket..."
aws s3 rm "s3://$TF_BACKEND_BUCKET" --recursive > /dev/null || true
  
echo -e "\n 2- Deleting S3 bucket..."
aws s3api delete-bucket --bucket "$TF_BACKEND_BUCKET" --region "$AWS_REGION" > /dev/null || true

echo -e "\n 3- Deleting DynamoDB table..."
aws dynamodb delete-table --table-name "$TF_BACKEND_DDB_TABLE" --region "$AWS_REGION" > /dev/null || true

echo -e "\n 4- Deleting IAM OIDC provider..."
aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" > /dev/null || true

echo -e "\n 5- Deleting IAM role inline policy..."
aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "${REPO}-inline-terraform" > /dev/null || true

echo -e "\n 6- Deleting IAM role..."
aws iam delete-role --role-name "$ROLE_NAME" > /dev/null || true


echo "Cleanup complete."