#!/usr/bin/env bash
# =============================================================================
# emergency-revoke.sh — Emergency secret revocation
# Revokes all credentials for a specific service immediately
# Use when a pod is compromised or credentials are suspected leaked
# Usage: ./emergency-revoke.sh --service payment-api --engine database
# =============================================================================

set -euo pipefail

SERVICE=""
ENGINE=""
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --service) SERVICE="$2"; shift 2 ;;
    --engine)  ENGINE="$2";  shift 2 ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

if [ -z "$SERVICE" ] || [ -z "$ENGINE" ]; then
  echo "Usage: $0 --service payment-api --engine database"
  exit 1
fi

export VAULT_ADDR VAULT_TOKEN

echo "⚠️  EMERGENCY REVOCATION"
echo "Service : $SERVICE"
echo "Engine  : $ENGINE"
echo ""
read -p "Type 'CONFIRM' to revoke all ${SERVICE} credentials: " CONFIRM
if [ "$CONFIRM" != "CONFIRM" ]; then
  echo "Aborted."
  exit 0
fi

echo "Revoking all ${ENGINE} credentials for ${SERVICE}..."

# Revoke by prefix — revokes all leases under the service path
vault lease revoke -prefix "${ENGINE}/creds/${SERVICE}-role"

echo "✅ All ${SERVICE} ${ENGINE} credentials revoked"
echo "   Affected pods will fail on next DB/API call"
echo "   Restart affected pods to obtain fresh credentials"
echo ""
echo "Post-revocation steps:"
echo "1. kubectl rollout restart deployment/${SERVICE} -n finance"
echo "2. Monitor pod logs for successful re-authentication"
echo "3. Check vault audit log for access during incident window"
