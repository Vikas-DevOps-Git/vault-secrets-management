#!/usr/bin/env bash
# =============================================================================
# setup-pki.sh — Configure Vault PKI for internal mTLS certificates
# Creates root CA, intermediate CA, and per-service certificate roles
# Certificates used for Istio mTLS and internal service-to-service auth
# Usage: ./setup-pki.sh --domain bny-internal.com
# =============================================================================

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-root}"
DOMAIN="${DOMAIN:-bny-internal.com}"
ORG="${ORG:-BNY Mellon Platform Engineering}"

export VAULT_ADDR VAULT_TOKEN

echo "=============================================="
echo " Vault PKI Setup"
echo " Domain: $DOMAIN"
echo " Org   : $ORG"
echo "=============================================="

# Step 1 — Root CA
echo "Step 1: Setting up Root CA..."
vault secrets enable -path=pki pki 2>/dev/null || echo "  (already enabled)"
vault secrets tune -max-lease-ttl=87600h pki

vault write -field=certificate pki/root/generate/internal \
  common_name="${ORG} Root CA" \
  organization="${ORG}" \
  ttl=87600h > /tmp/root-ca.crt

vault write pki/config/urls \
  issuing_certificates="${VAULT_ADDR}/v1/pki/ca" \
  crl_distribution_points="${VAULT_ADDR}/v1/pki/crl"

echo "  ✅ Root CA created"

# Step 2 — Intermediate CA
echo "Step 2: Setting up Intermediate CA..."
vault secrets enable -path=pki_int pki 2>/dev/null || echo "  (already enabled)"
vault secrets tune -max-lease-ttl=43800h pki_int

# Generate intermediate CSR
vault write -format=json pki_int/intermediate/generate/internal \
  common_name="${ORG} Intermediate CA" \
  organization="${ORG}" \
  | jq -r '.data.csr' > /tmp/int-ca.csr

# Sign with root CA
vault write -format=json pki/root/sign-intermediate \
  csr=@/tmp/int-ca.csr \
  format=pem_bundle \
  ttl=43800h \
  | jq -r '.data.certificate' > /tmp/int-ca.crt

# Import signed certificate
vault write pki_int/intermediate/set-signed \
  certificate=@/tmp/int-ca.crt

vault write pki_int/config/urls \
  issuing_certificates="${VAULT_ADDR}/v1/pki_int/ca" \
  crl_distribution_points="${VAULT_ADDR}/v1/pki_int/crl"

echo "  ✅ Intermediate CA created and signed"

# Step 3 — Certificate roles per service
echo "Step 3: Creating certificate roles..."

# Payment API — 24h certificates for mTLS
vault write pki_int/roles/payment-api \
  allowed_domains="${DOMAIN},payment-api.finance.svc.cluster.local" \
  allow_subdomains=true \
  allow_localhost=true \
  key_type=rsa \
  key_bits=2048 \
  max_ttl=24h \
  ttl=24h \
  require_cn=true \
  server_flag=true \
  client_flag=true

echo "  ✅ PKI role: payment-api (24h, mTLS)"

# Internal services — 72h certificates
vault write pki_int/roles/internal-services \
  allowed_domains="${DOMAIN},svc.cluster.local" \
  allow_subdomains=true \
  key_type=rsa \
  key_bits=2048 \
  max_ttl=72h \
  ttl=24h \
  server_flag=true \
  client_flag=true

echo "  ✅ PKI role: internal-services (72h max)"

# Step 4 — Test certificate issuance
echo "Step 4: Testing certificate issuance..."
vault write pki_int/issue/payment-api \
  common_name="payment-api.finance.svc.cluster.local" \
  ttl=24h > /dev/null

echo "  ✅ Test certificate issued successfully"

echo ""
echo "=============================================="
echo " ✅ PKI configured"
echo ""
echo " To issue a certificate:"
echo "   vault write pki_int/issue/payment-api"
echo "   common_name=payment-api.finance.svc.cluster.local"
echo "   ttl=24h"
echo "=============================================="
