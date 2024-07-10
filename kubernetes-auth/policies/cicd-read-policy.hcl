# cicd-read-policy.hcl
# CI/CD pipeline — read build secrets only
# Short TTL (15 min) prevents credential exposure if pipeline is compromised

# Docker registry credentials
path "secret/data/cicd/docker-registry" {
  capabilities = ["read"]
}

# SonarQube token
path "secret/data/cicd/sonarqube" {
  capabilities = ["read"]
}

# Terraform state bucket credentials
path "secret/data/cicd/terraform-state" {
  capabilities = ["read"]
}

# AWS ECR push credentials (short-lived)
path "aws/creds/cicd-ecr-role" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
