# Terraform module — Vault Kubernetes auth configuration
# Manages auth method, backend config, and roles via code

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = var.auth_path

  tune {
    default_lease_ttl  = "1h"
    max_lease_ttl      = "4h"
    token_type         = "default-service"
  }
}

resource "vault_kubernetes_auth_backend_config" "main" {
  backend            = vault_auth_backend.kubernetes.path
  kubernetes_host    = var.kubernetes_host
  kubernetes_ca_cert = var.kubernetes_ca_cert
  issuer             = var.token_issuer
}

# Dynamic role creation from var.roles map
resource "vault_kubernetes_auth_backend_role" "roles" {
  for_each = var.roles

  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = each.key
  bound_service_account_names      = each.value.service_accounts
  bound_service_account_namespaces = each.value.namespaces
  token_policies                   = each.value.policies
  token_ttl                        = each.value.ttl
  token_max_ttl                    = each.value.max_ttl
}
