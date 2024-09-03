#!/usr/bin/env bash
# =============================================================================
# setup-aws-secrets.sh — Configure Vault AWS dynamic credentials
# Creates IAM users or AssumeRole-based temporary credentials per service
# Usage: ./setup-aws-secrets.sh --access-key AKID --secret-key SECRET
# =============================================================================

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-root}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCESS_KEY="${AWS_ACCESS_KEY:-}"
AWS_SECRET_KEY="${AWS_SECRET_KEY:-}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --access-key) AWS_ACCESS_KEY="$2"; shift 2 ;;
    --secret-key) AWS_SECRET_KEY="$2"; shift 2 ;;
    --region)     AWS_REGION="$2";     shift 2 ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

export VAULT_ADDR VAULT_TOKEN

echo "=============================================="
echo " Vault AWS Dynamic Credentials Setup"
echo " Region: $AWS_REGION"
echo "=============================================="

# Enable AWS secrets engine
vault secrets enable aws 2>/dev/null || echo "  (already enabled)"

# Configure root AWS credentials
vault write aws/config/root \
  access_key="${AWS_ACCESS_KEY}" \
  secret_key="${AWS_SECRET_KEY}" \
  region="${AWS_REGION}"

# Rotate root credentials immediately
vault write -force aws/config/rotate-root
echo "✅ AWS root credentials rotated"

# Role: payment-api — S3 read for configs, CloudWatch write for metrics
vault write aws/roles/payment-api-aws-role \
  credential_type=iam_user \
  policy_document='{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": ["s3:GetObject", "s3:ListBucket"],
        "Resource": [
          "arn:aws:s3:::bny-payment-configs",
          "arn:aws:s3:::bny-payment-configs/*"
        ]
      },
      {
        "Effect": "Allow",
        "Action": [
          "cloudwatch:PutMetricData",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource": "*"
      }
    ]
  }' \
  default_ttl="1h" \
  max_ttl="4h"

echo "✅ AWS role: payment-api-aws-role (S3 read + CloudWatch write)"

# Role: cicd-ecr — push images to ECR during CI pipeline
vault write aws/roles/cicd-ecr-role \
  credential_type=assumed_role \
  role_arns="arn:aws:iam::123456789012:role/cicd-ecr-push-role" \
  default_ttl="15m" \
  max_ttl="30m"

echo "✅ AWS role: cicd-ecr-role (ECR push, 15 min TTL)"

echo ""
echo "=============================================="
echo " ✅ AWS dynamic credentials configured"
echo ""
echo " To get credentials:"
echo "   vault read aws/creds/payment-api-aws-role"
echo "   vault read aws/creds/cicd-ecr-role"
echo "=============================================="
