# Vault Kubernetes Auth — Setup and Usage Guide

## Overview

Kubernetes auth method lets pods authenticate to Vault using their
ServiceAccount JWT token. No static credentials required — the pod's
identity is verified against the Kubernetes API server.

## How It Works

```
Pod                    Vault                  Kubernetes API
 |                       |                         |
 |-- POST /auth/k8s/login|                         |
 |   {jwt, role}         |                         |
 |                       |-- TokenReview API ------>|
 |                       |<-- SA name, namespace ---|
 |                       |                         |
 |                       |-- Check bound_sa, ns    |
 |                       |-- Attach policies        |
 |<-- Vault token --------|                         |
```

## Quick Setup

```bash
# Configure auth backend
./kubernetes-auth/setup-k8s-auth.sh \
  --vault-addr http://vault:8200 \
  --cluster-name bny-platform

# Verify from inside a pod
kubectl exec -it payment-api-xxx -n finance -- \
  ./scripts/verify-vault-auth.sh
```

## Role Design Principles

Each role maps exactly one ServiceAccount to one set of policies.
This ensures each pod has the minimum permissions needed:

| Role | Service Account | Namespace | TTL |
|---|---|---|---|
| payment-api | payment-api-sa | finance | 1h |
| notification-service | notification-service-sa | finance | 1h |
| vault-rotation | vault-rotation-sa | vault-system | 30m |
| cicd-pipeline | cicd-sa | cicd | 15m |

## Adding a New Service

1. Create a ServiceAccount in Kubernetes
2. Add a policy HCL file in `kubernetes-auth/policies/`
3. Run `setup-k8s-auth.sh` to create the role
4. Add Vault Agent annotations to the deployment
