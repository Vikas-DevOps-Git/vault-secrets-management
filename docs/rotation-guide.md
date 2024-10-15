# Vault Secret Rotation Guide

## Automated Rotation via CronJob

The vault-rotation CronJob runs every 6 hours and renews all leases
expiring within 24 hours. Deploy it once and rotation is fully automated:

```bash
kubectl apply -f rotation/cronjobs/vault-rotation-cronjob.yaml

# Verify CronJob is scheduled
kubectl get cronjob -n vault-system

# Trigger manual run
kubectl create job --from=cronjob/vault-lease-rotation \
  manual-rotation-$(date +%s) -n vault-system

# Check logs
kubectl logs -l app=vault-rotation -n vault-system
```

## Manual Rotation

```bash
# Using the Bash script (for ops team)
./rotation/scripts/rotate-all.sh \
  --vault-addr http://vault:8200 \
  --k8s-role vault-rotation \
  --threshold-hours 24

# Using the Python script (for CI/CD)
python -m vault_rotation.main \
  --vault-addr http://vault:8200 \
  --k8s-role vault-rotation \
  --threshold-hours 24 \
  --output json
```

## Root Credential Rotation

After initial setup, rotate the database admin password so Vault owns it:

```bash
# Database root credential rotation
vault write -force database/rotate-root/finance-postgres

# AWS root credential rotation
vault write -force aws/config/rotate-root

# After rotation, original credentials are invalid
# Only Vault can generate new credentials
```

## Audit Trail

All Vault operations are logged to the audit log:

```bash
# Enable file audit log
vault audit enable file file_path=/var/log/vault-audit.log

# View recent auth events
tail -f /var/log/vault-audit.log | \
  python3 -c "import sys,json; [print(json.dumps(json.loads(l), indent=2)) for l in sys.stdin]"
```
