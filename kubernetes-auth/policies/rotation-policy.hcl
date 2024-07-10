# rotation-policy.hcl
# Vault rotation CronJob — list and renew leases across all app paths
# Restricted to renewal only — cannot read secret values

# List and renew leases under app paths
path "sys/leases/lookup" {
  capabilities = ["update"]
}

path "sys/leases/renew" {
  capabilities = ["update"]
}

path "sys/leases/list/*" {
  capabilities = ["list", "update"]
}

# Renew own token
path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# Read lease metadata (TTL) but NOT secret values
path "database/creds/*" {
  capabilities = []
}
