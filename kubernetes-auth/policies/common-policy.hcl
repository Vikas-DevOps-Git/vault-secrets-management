# common-policy.hcl
# Applied to all application pods regardless of service.
# Minimal baseline — only token self-management.

# Token renewal — prevent pod auth expiry on long-running workloads
path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Token lookup — pods can check their own TTL
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# Sys health — pods can check Vault availability
path "sys/health" {
  capabilities = ["read"]
}
