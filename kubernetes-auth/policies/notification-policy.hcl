# notification-policy.hcl
# Notification service — read own secrets, no DB or AWS access

path "secret/data/finance/notification-service/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/finance/notification-service/*" {
  capabilities = ["list"]
}

# Slack webhook URL stored in Vault
path "secret/data/integrations/slack" {
  capabilities = ["read"]
}

# PagerDuty routing key
path "secret/data/integrations/pagerduty" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
