# postgres-roles.hcl — Vault policy for reading dynamic DB credentials
# Applied via payment-api-policy.hcl — shown here for documentation

# Payment API — full CRUD credentials
path "database/creds/payment-api-role" {
  capabilities = ["read"]
}

# Notification service — read-only credentials  
path "database/creds/notification-role" {
  capabilities = ["read"]
}

# Analytics — read-only across all schemas
path "database/creds/readonly-role" {
  capabilities = ["read"]
}
