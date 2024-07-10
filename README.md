# vault-secrets-management

Production-grade HashiCorp Vault configuration for Kubernetes environments.
Covers Kubernetes auth method, dynamic database and AWS credentials, PKI
certificate management, automated lease rotation, and Vault Agent sidecar injection.

Built and operated at BNY Mellon supporting zero-hardcoded-credentials
across 100+ microservices on AWS EKS in a SOX-regulated environment.

---

## What This Repo Covers

| Area | What Is Included |
|---|---|
| **Kubernetes Auth** | Auth method setup, per-service roles, HCL policies, verify script |
| **Dynamic Secrets** | PostgreSQL, AWS IAM, PKI/mTLS certificate issuance |
| **Rotation** | Automated CronJob, Bash rotation script, emergency revocation |
| **Vault Agent** | Sidecar annotation pattern — secrets injected without SDK |
| **Terraform** | Vault configuration as code — auth, secrets engines, policies, roles |
| **Python** | Idempotent vault_setup.py with dry run and policy loading |
| **Tests** | Unit tests for vault_setup.py — no Vault server required |
| **CI/CD** | GitHub Actions: Terraform validate, HCL lint, pytest, shellcheck |

---

## Repository Structure

```
vault-secrets-management/
├── kubernetes-auth/
│   ├── setup-k8s-auth.sh             # Configure K8s auth method and roles
│   ├── policies/
│   │   ├── payment-api-policy.hcl    # DB creds + KV + AWS + PKI
│   │   ├── notification-policy.hcl   # KV read + integrations
│   │   ├── common-policy.hcl         # Token renewal — all pods
│   │   ├── rotation-policy.hcl       # Lease renewal — no secret read
│   │   └── cicd-read-policy.hcl      # CI/CD build secrets only
│   └── roles/                        # Role definitions (managed by setup script)
├── dynamic-secrets/
│   ├── database/
│   │   ├── setup-db-secrets.sh       # PostgreSQL engine + roles + root rotation
│   │   └── postgres-roles.hcl        # Policy snippets for DB access
│   ├── aws/
│   │   └── setup-aws-secrets.sh      # AWS engine + per-service IAM roles
│   └── pki/
│       └── setup-pki.sh              # Root CA + Intermediate CA + cert roles
├── rotation/
│   ├── scripts/
│   │   ├── rotate-all.sh             # Master rotation script (all engines)
│   │   └── emergency-revoke.sh       # Immediate revocation for compromised pods
│   └── cronjobs/
│       └── vault-rotation-cronjob.yaml  # K8s CronJob — every 6 hours
├── helm/
│   └── vault-agent/
│       ├── Chart.yaml
│       ├── templates/
│       │   └── deployment-with-agent.yaml  # Vault Agent sidecar annotation pattern
│       └── values.yaml
├── terraform/
│   └── vault-config/
│       ├── modules/
│       │   ├── kubernetes-auth/      # K8s auth as Terraform resource
│       │   ├── dynamic-secrets/      # DB engine and roles
│       │   └── policies/             # vault_policy resources
│       ├── environments/
│       │   ├── dev/                  # Dev environment wiring
│       │   └── prod/                 # Prod environment wiring
│       └── policies/                 # HCL files referenced by Terraform
├── scripts/
│   ├── vault_setup.py                # Idempotent Python setup script
│   └── verify-vault-auth.sh          # Test K8s auth from inside a pod
├── tests/
│   └── test_vault_setup.py           # Unit tests — no Vault server needed
├── docs/
│   ├── kubernetes-auth-guide.md
│   ├── dynamic-secrets-guide.md
│   └── rotation-guide.md
└── .github/workflows/
    └── validate.yml                  # Terraform validate + HCL lint + pytest
```

---

## Quick Start

### Prerequisites

```bash
vault >= 1.15
kubectl >= 1.29
terraform >= 1.6
python >= 3.9
pip install hvac pytest
```

### 1 — Initial Vault Setup

```bash
# Automated setup via Python (idempotent — safe to re-run)
python scripts/vault_setup.py \
  --vault-addr http://vault:8200 \
  --vault-token root \
  --k8s-host https://kubernetes.default.svc \
  --policy-dir kubernetes-auth/policies

# Or step by step via shell scripts:
./kubernetes-auth/setup-k8s-auth.sh \
  --vault-addr http://vault:8200 \
  --cluster-name bny-platform

./dynamic-secrets/database/setup-db-secrets.sh \
  --db-host postgres.finance.internal \
  --db-password "$DB_ADMIN_PASSWORD"

./dynamic-secrets/pki/setup-pki.sh \
  --domain bny-internal.com
```

### 2 — Deploy Vault Agent Sidecar

```bash
# Install Vault Agent Injector via Helm
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault \
  --set "injector.enabled=true" \
  --set "server.enabled=false" \
  -n vault --create-namespace

# Deploy application with sidecar annotations
helm install payment-api helm/vault-agent/ \
  -n finance --create-namespace
```

### 3 — Verify Auth From Inside a Pod

```bash
kubectl exec -it payment-api-xxx -n finance -- \
  bash -c "$(cat scripts/verify-vault-auth.sh)"
```

### 4 — Deploy Rotation CronJob

```bash
kubectl apply -f rotation/cronjobs/vault-rotation-cronjob.yaml

# Check it runs
kubectl get cronjob -n vault-system
kubectl get jobs -n vault-system
```

---

## Kubernetes Auth Flow

```
Pod (ServiceAccount JWT)
        │
        ▼
Vault /auth/kubernetes/login
        │
        ▼
Vault → Kubernetes TokenReview API
        │  (verify JWT is valid)
        ▼
Vault checks bound_service_account_names
     and bound_service_account_namespaces
        │
        ▼
Vault attaches policies → issues token (TTL 1h)
        │
        ▼
Pod reads dynamic DB creds / KV secrets / AWS creds
```

---

## Dynamic Database Credentials

```bash
# Every read generates a unique temporary credential
vault read database/creds/payment-api-role

# Key             Value
# lease_id        database/creds/payment-api-role/abc123
# lease_duration  1h0m0s
# username        v-k8s-payment-AbCd1234
# password        A1b2-generated-unique-password

# Credential auto-revokes at DB level after 1 hour
# No shared passwords — each pod gets its own identity in audit logs
```

---

## Vault Agent Sidecar — Zero SDK Pattern

Applications read secrets from files — no Vault SDK needed:

```yaml
annotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/role: "payment-api"
  vault.hashicorp.com/agent-inject-secret-db-creds: "database/creds/payment-api-role"
  vault.hashicorp.com/agent-inject-template-db-creds: |
    {{- with secret "database/creds/payment-api-role" -}}
    export DB_USERNAME="{{ .Data.username }}"
    export DB_PASSWORD="{{ .Data.password }}"
    {{- end }}
```

App startup:
```bash
source /vault/secrets/db-creds
exec node app.js
```

---

## Policy Design Principles

All policies follow least-privilege — each role can only read its own secrets:

| Policy | Can Read | Cannot Read |
|---|---|---|
| payment-api-policy | Own DB creds, own KV, own AWS | Other services' secrets |
| rotation-policy | Lease metadata only | Secret values |
| cicd-read-policy | Build secrets, ECR creds | Application secrets |
| common-policy | Token self-management | Anything else |

---

## Emergency Revocation

```bash
# Immediately revoke ALL credentials for a compromised service
./rotation/scripts/emergency-revoke.sh \
  --service payment-api \
  --engine database

# Restart pod to force re-authentication with fresh credentials
kubectl rollout restart deployment/payment-api -n finance
```

---

## Tests

```bash
# Unit tests — no Vault server required
pip install hvac pytest pytest-mock
pytest tests/ -v

# Dry run setup — show what would be configured
python scripts/vault_setup.py \
  --vault-addr http://localhost:8200 \
  --vault-token root \
  --dry-run
```

---

## SLO Impact

| Before Vault | After Vault |
|---|---|
| Static DB password in Kubernetes Secret | Dynamic credential, unique per pod, 1h TTL |
| Shared AWS keys in environment variables | Per-service IAM role, 1h temporary credentials |
| Certificates managed manually | Auto-issued via PKI, 24h TTL, auto-renewed |
| Credential breach = manual rotation across all services | Breach = single lease revoke + pod restart |
| No audit trail per pod | Full audit log with per-pod identity |

---

## Author

Vikas Dhamija — Senior DevOps Engineer | VP Platform Engineering, BNY Mellon
GitHub: https://github.com/Vikas-DevOps-Git
