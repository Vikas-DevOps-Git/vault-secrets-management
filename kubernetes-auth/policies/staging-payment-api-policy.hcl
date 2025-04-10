# staging-payment-api-policy.hcl
# Scoped to staging namespace — prevents staging pods reading prod secrets

path "secret/data/staging/payment-api/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/staging/payment-api/*" {
  capabilities = ["list"]
}

path "database/creds/staging-payment-api-role" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
