# admin-policy.hcl
# Platform team admin — full access for break-glass scenarios
# Assigned only to platform-admin Vault group — never to pods

# Full access to all secret engines
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "database/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "aws/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "pki/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "pki_int/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Sys management
path "sys/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Auth management
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
