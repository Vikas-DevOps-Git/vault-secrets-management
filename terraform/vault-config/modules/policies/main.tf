# Vault policies managed as Terraform resources
# Policy files stored as .hcl in this module directory

resource "vault_policy" "policies" {
  for_each = var.policies
  name     = each.key
  policy   = each.value
}
