# payment-api-policy.hcl
# Grants payment-api pods read access to their own secrets only.
# Scope: finance namespace, payment-api service only.
# No write access — secrets are managed by platform team via Terraform.

# Dynamic database credentials — read-only
path "database/creds/payment-api-role" {
  capabilities = ["read"]
}

# KV v2 — read own secrets, list to discover paths
path "secret/data/finance/payment-api/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/finance/payment-api/*" {
  capabilities = ["list"]
}

# AWS IAM dynamic credentials — read-only
path "aws/creds/payment-api-aws-role" {
  capabilities = ["read"]
}

# PKI — issue certificates for mTLS
path "pki/issue/payment-api" {
  capabilities = ["create", "update"]
}

# Allow token renewal (required for long-running pods)
path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Allow token lookup (pods check their own token TTL)
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
