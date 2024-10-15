#!/usr/bin/env bash
# =============================================================================
# rotate-all.sh — Master rotation script
# Renews all expiring leases across database, AWS, and PKI engines
# Designed to run as a Kubernetes CronJob every 6 hours
# Usage: ./rotate-all.sh --vault-addr http://vault:8200 --k8s-role vault-rotation
# =============================================================================

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"
K8S_ROLE="${K8S_ROLE:-vault-rotation}"
THRESHOLD_HOURS="${THRESHOLD_HOURS:-24}"
DRY_RUN="${DRY_RUN:-false}"
LOG_FILE="${LOG_FILE:-/var/log/vault-rotation.log}"
JWT_PATH="/var/run/secrets/kubernetes.io/serviceaccount/token"

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" | tee -a "$LOG_FILE"; }
log_json() { echo "$*" >> "${LOG_FILE%.log}.json"; }

log "=============================================="
log " Vault Rotation Starting"
log " Vault  : $VAULT_ADDR"
log " K8s Role: $K8S_ROLE"
log " Threshold: ${THRESHOLD_HOURS}h"
log " Dry run: $DRY_RUN"
log "=============================================="

# Authenticate — Kubernetes auth preferred, fallback to token
if [ -f "$JWT_PATH" ] && [ -n "$K8S_ROLE" ]; then
  log "Authenticating via Kubernetes auth..."
  JWT=$(cat "$JWT_PATH")
  VAULT_TOKEN=$(curl -s \
    --request POST \
    --data "{\"jwt\":\"${JWT}\",\"role\":\"${K8S_ROLE}\"}" \
    "${VAULT_ADDR}/v1/auth/kubernetes/login" | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['auth']['client_token'])")
  export VAULT_TOKEN
  log "✅ Authenticated via Kubernetes auth"
elif [ -n "$VAULT_TOKEN" ]; then
  log "Using provided VAULT_TOKEN"
else
  log "ERROR: No authentication method available"
  exit 1
fi

# Renew own token first
log "Renewing self token..."
vault token renew-self -increment=6h > /dev/null 2>&1 && \
  log "✅ Token renewed" || log "⚠️  Token renewal failed"

# Helper — check and renew a lease
renew_if_expiring() {
  local lease_id="$1"
  local ttl

  ttl=$(vault lease lookup "$lease_id" 2>/dev/null | \
    grep "^ttl" | awk '{print $2}' || echo "99999")

  if [ "$ttl" -lt "$((THRESHOLD_HOURS * 3600))" ] 2>/dev/null; then
    log "Lease $lease_id TTL=${ttl}s — below threshold, renewing"
    if [ "$DRY_RUN" = "true" ]; then
      log "[DRY RUN] Would renew $lease_id"
    else
      vault lease renew "$lease_id" -increment=3600 > /dev/null 2>&1 && \
        log "✅ Renewed: $lease_id" || \
        log "❌ Failed:  $lease_id"
    fi
  else
    log "Lease $lease_id TTL=${ttl}s — OK, skipping"
  fi
}

# Rotate database credentials
log ""
log "--- Database credential rotation ---"
for path in database/creds/ ; do
  leases=$(vault list sys/leases/lookup/${path} 2>/dev/null || echo "")
  if [ -n "$leases" ]; then
    for lease in $leases; do
      renew_if_expiring "${path}${lease}"
    done
  else
    log "No active leases under ${path}"
  fi
done

# Rotate AWS credentials
log ""
log "--- AWS credential rotation ---"
for path in aws/creds/ ; do
  leases=$(vault list sys/leases/lookup/${path} 2>/dev/null || echo "")
  if [ -n "$leases" ]; then
    for lease in $leases; do
      renew_if_expiring "${path}${lease}"
    done
  else
    log "No active leases under ${path}"
  fi
done

# Rotate PKI certificates approaching expiry
log ""
log "--- PKI certificate rotation ---"
for path in pki_int/issue/ ; do
  leases=$(vault list sys/leases/lookup/${path} 2>/dev/null || echo "")
  if [ -n "$leases" ]; then
    for lease in $leases; do
      renew_if_expiring "${path}${lease}"
    done
  else
    log "No active PKI leases"
  fi
done

log ""
log "=============================================="
log " ✅ Rotation complete"
log "=============================================="
