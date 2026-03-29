#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="eu-west-2"
STATE_BUCKET="n8n-taurak-tfstate"
LOCK_TABLE="n8n-taurak-state-lock"

aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null || \
  aws s3api create-bucket --bucket "$STATE_BUCKET" --region "$AWS_REGION" \
    --create-bucket-configuration LocationConstraint="$AWS_REGION"

aws s3api put-bucket-versioning --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled

aws dynamodb describe-table --table-name "$LOCK_TABLE" --region "$AWS_REGION" 2>/dev/null || \
  aws dynamodb create-table --table-name "$LOCK_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$AWS_REGION"
