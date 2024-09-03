# Dynamic Secrets — Database, AWS, PKI

## Database Dynamic Credentials

Instead of a static password, each pod gets a unique temporary credential
with a 1-hour TTL. When the TTL expires, the credential is automatically
revoked at the database level.

```bash
# Get a temporary credential
vault read database/creds/payment-api-role

# Output:
# Key                Value
# lease_id           database/creds/payment-api-role/abc123
# lease_duration     1h
# username           v-payment-1234
# password           A1b2C3d4-generated
```

### Benefits over static passwords

| Static Password | Dynamic Credential |
|---|---|
| Stored in secret or env var | Never stored anywhere |
| Never expires | Expires in 1 hour |
| Revocation requires password change | Revoke by lease ID |
| Shared across all pods | Unique per pod |
| Audit log shows "app" | Audit log shows "v-payment-1234" |

## AWS Dynamic Credentials

```bash
# Get temporary AWS credentials
vault read aws/creds/payment-api-aws-role

# Output:
# access_key     ASIA...
# secret_key     wJalrXUt...
# security_token SESSION_TOKEN
# lease_duration 1h
```

## PKI Certificate Issuance

```bash
# Issue a certificate for mTLS
vault write pki_int/issue/payment-api \
  common_name=payment-api.finance.svc.cluster.local \
  ttl=24h

# Returns: certificate, private_key, ca_chain, serial_number
```

## Emergency Revocation

If a pod is compromised, revoke all its credentials immediately:

```bash
./rotation/scripts/emergency-revoke.sh \
  --service payment-api \
  --engine database

# Then restart the pod to force re-authentication
kubectl rollout restart deployment/payment-api -n finance
```
