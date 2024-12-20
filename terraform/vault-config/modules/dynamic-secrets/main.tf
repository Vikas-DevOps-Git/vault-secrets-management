# Dynamic secrets module — database engine + roles

resource "vault_mount" "database" {
  path        = "database"
  type        = "database"
  description = "Dynamic database credentials for ${var.environment}"
}

resource "vault_database_secret_backend_connection" "postgres" {
  backend       = vault_mount.database.path
  name          = "${var.environment}-postgres"
  allowed_roles = [for r in var.db_roles : r.name]

  postgresql {
    connection_url = "postgresql://{{username}}:{{password}}@${var.db_host}:${var.db_port}/${var.db_name}?sslmode=require"
    username       = var.db_admin_user
    password       = var.db_admin_password
  }
}

resource "vault_database_secret_backend_role" "roles" {
  for_each = { for r in var.db_roles : r.name => r }

  backend             = vault_mount.database.path
  name                = each.value.name
  db_name             = vault_database_secret_backend_connection.postgres.name
  creation_statements = each.value.creation_sql
  revocation_statements = [
    "REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM \"{{name}}\"; DROP ROLE IF EXISTS \"{{name}}\";"
  ]
  default_ttl = each.value.ttl
  max_ttl     = each.value.max_ttl
}
