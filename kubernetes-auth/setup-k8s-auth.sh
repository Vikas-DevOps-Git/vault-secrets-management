#!/usr/bin/env bash
# =============================================================================
# setup-k8s-auth.sh — Configure Vault Kubernetes auth method
# Enables K8s auth, configures cluster connection, creates roles per namespace
# Usage: ./setup-k8s-auth.sh --vault-addr http://vault:8200 --cluster-name bny-platform
# =============================================================================

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-root}"
CLUSTER_NAME="bny-platform"
K8S_HOST=""
AUTH_PATH="kubernetes"

while [[ $# -gt 0 ]]; do
  case $1 in
    --vault-addr)    VAULT_ADDR="$2";    shift 2 ;;
    --vault-token)   VAULT_TOKEN="$2";   shift 2 ;;
    --cluster-name)  CLUSTER_NAME="$2";  shift 2 ;;
    --k8s-host)      K8S_HOST="$2";      shift 2 ;;
    --auth-path)     AUTH_PATH="$2";     shift 2 ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

export VAULT_ADDR VAULT_TOKEN

echo "=============================================="
echo " Vault Kubernetes Auth Setup"
echo " Vault  : $VAULT_ADDR"
echo " Cluster: $CLUSTER_NAME"
echo "=============================================="

# Step 1 — Enable Kubernetes auth method
echo ""
echo "Step 1: Enabling Kubernetes auth method at path: ${AUTH_PATH}"
vault auth enable -path="${AUTH_PATH}" kubernetes 2>/dev/null || \
  echo "  (already enabled)"

# Step 2 — Configure K8s auth backend
echo ""
echo "Step 2: Configuring Kubernetes auth backend..."

if [ -z "$K8S_HOST" ]; then
  # Auto-detect from in-cluster
  K8S_HOST="https://kubernetes.default.svc.cluster.local"
  echo "  Using in-cluster K8s host: $K8S_HOST"
fi

# Get cluster CA cert
K8S_CA_CERT=$(kubectl config view --raw --minify \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' 2>/dev/null | \
  base64 --decode || echo "")

if [ -n "$K8S_CA_CERT" ]; then
  vault write auth/${AUTH_PATH}/config \
    kubernetes_host="${K8S_HOST}" \
    kubernetes_ca_cert="${K8S_CA_CERT}"
else
  vault write auth/${AUTH_PATH}/config \
    kubernetes_host="${K8S_HOST}"
fi

echo "  ✅ Kubernetes auth configured"

# Step 3 — Create roles per namespace/service
echo ""
echo "Step 3: Creating Kubernetes auth roles..."

# Payment API role — finance namespace
vault write auth/${AUTH_PATH}/role/payment-api \
  bound_service_account_names="payment-api-sa" \
  bound_service_account_namespaces="finance" \
  policies="payment-api-policy,common-policy" \
  ttl=1h \
  max_ttl=4h

echo "  ✅ Role: payment-api (namespace: finance)"

# Notification service role
vault write auth/${AUTH_PATH}/role/notification-service \
  bound_service_account_names="notification-service-sa" \
  bound_service_account_namespaces="finance" \
  policies="notification-policy,common-policy" \
  ttl=1h \
  max_ttl=4h

echo "  ✅ Role: notification-service (namespace: finance)"

# Vault rotation script role — least privilege
vault write auth/${AUTH_PATH}/role/vault-rotation \
  bound_service_account_names="vault-rotation-sa" \
  bound_service_account_namespaces="vault-system" \
  policies="rotation-policy" \
  ttl=30m \
  max_ttl=1h

echo "  ✅ Role: vault-rotation (namespace: vault-system)"

# CI/CD role — for GitHub Actions / Jenkins
vault write auth/${AUTH_PATH}/role/cicd-pipeline \
  bound_service_account_names="cicd-sa" \
  bound_service_account_namespaces="cicd" \
  policies="cicd-read-policy" \
  ttl=15m \
  max_ttl=30m

echo "  ✅ Role: cicd-pipeline (namespace: cicd)"

# Step 4 — Verify configuration
echo ""
echo "Step 4: Verifying auth configuration..."
vault read auth/${AUTH_PATH}/config
echo ""
vault list auth/${AUTH_PATH}/role

echo ""
echo "=============================================="
echo " ✅ Kubernetes auth setup complete"
echo " Test login:"
echo "   vault write auth/${AUTH_PATH}/login"
echo "   role=payment-api"
echo "   jwt=\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
echo "=============================================="
