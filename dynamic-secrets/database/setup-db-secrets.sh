#!/usr/bin/env bash
# =============================================================================
# setup-db-secrets.sh — Configure Vault dynamic database secrets
# Creates DB secret engine, connection config, and roles per service
# Supports: PostgreSQL, MySQL
# Usage: ./setup-db-secrets.sh --db-host postgres.finance.internal --db-password SECRET
# =============================================================================

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-root}"
DB_HOST="${DB_HOST:-postgres.finance.internal}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-financedb}"
DB_ADMIN_USER="${DB_ADMIN_USER:-vault_admin}"
DB_PASSWORD="${DB_PASSWORD:-}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --db-host)     DB_HOST="$2";     shift 2 ;;
    --db-port)     DB_PORT="$2";     shift 2 ;;
    --db-name)     DB_NAME="$2";     shift 2 ;;
    --db-user)     DB_ADMIN_USER="$2"; shift 2 ;;
    --db-password) DB_PASSWORD="$2"; shift 2 ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

export VAULT_ADDR VAULT_TOKEN

echo "=============================================="
echo " Vault Dynamic DB Secrets Setup"
echo " Host   : $DB_HOST:$DB_PORT"
echo " DB     : $DB_NAME"
echo "=============================================="

# Step 1 — Enable database secrets engine
echo ""
echo "Step 1: Enabling database secrets engine..."
vault secrets enable database 2>/dev/null || echo "  (already enabled)"

# Step 2 — Configure PostgreSQL connection
echo ""
echo "Step 2: Configuring PostgreSQL connection..."
vault write database/config/finance-postgres \
  plugin_name=postgresql-database-plugin \
  allowed_roles="payment-api-role,notification-role,readonly-role" \
  connection_url="postgresql://{{username}}:{{password}}@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require" \
  username="${DB_ADMIN_USER}" \
  password="${DB_PASSWORD}" \
  password_authentication="scram-sha-256"

echo "  ✅ PostgreSQL connection configured"

# Step 3 — Rotate admin password immediately (security best practice)
echo ""
echo "Step 3: Rotating admin password (removing static credential)..."
vault write -force database/rotate-root/finance-postgres
echo "  ✅ Admin password rotated — original credential no longer valid"

# Step 4 — Create roles per service
echo ""
echo "Step 4: Creating database roles..."

# Payment API role — full CRUD on payment tables
vault write database/roles/payment-api-role \
  db_name=finance-postgres \
  creation_statements="
    CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA payment TO \"{{name}}\";
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA payment TO \"{{name}}\";
    ALTER DEFAULT PRIVILEGES IN SCHEMA payment
      GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO \"{{name}}\";
  " \
  revocation_statements="
    REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA payment FROM \"{{name}}\";
    DROP ROLE IF EXISTS \"{{name}}\";
  " \
  default_ttl="1h" \
  max_ttl="4h"

echo "  ✅ Role: payment-api-role (TTL 1h, max 4h)"

# Notification service role — read-only
vault write database/roles/notification-role \
  db_name=finance-postgres \
  creation_statements="
    CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';
    GRANT SELECT ON ALL TABLES IN SCHEMA notification TO \"{{name}}\";
  " \
  revocation_statements="
    REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA notification FROM \"{{name}}\";
    DROP ROLE IF EXISTS \"{{name}}\";
  " \
  default_ttl="1h" \
  max_ttl="2h"

echo "  ✅ Role: notification-role (read-only, TTL 1h)"

# Read-only role — analytics and reporting
vault write database/roles/readonly-role \
  db_name=finance-postgres \
  creation_statements="
    CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";
    GRANT SELECT ON ALL TABLES IN SCHEMA payment TO \"{{name}}\";
    GRANT SELECT ON ALL TABLES IN SCHEMA notification TO \"{{name}}\";
  " \
  revocation_statements="
    DROP ROLE IF EXISTS \"{{name}}\";
  " \
  default_ttl="2h" \
  max_ttl="8h"

echo "  ✅ Role: readonly-role (all schemas read-only, TTL 2h)"

# Step 5 — Test credential generation
echo ""
echo "Step 5: Testing dynamic credential generation..."
vault read database/creds/payment-api-role
echo "  ✅ Dynamic credential generated and immediately valid"
echo "  (This credential expires in 1 hour and auto-revokes)"

echo ""
echo "=============================================="
echo " ✅ Database dynamic secrets configured"
echo ""
echo " To get credentials:"
echo "   vault read database/creds/payment-api-role"
echo "   vault read database/creds/readonly-role"
echo "=============================================="
