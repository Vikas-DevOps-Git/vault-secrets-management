terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.20"
    }
  }
  backend "s3" {
    bucket         = "bny-terraform-state-dev"
    key            = "vault-config/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "bny-terraform-locks"
    encrypt        = true
  }
}

provider "vault" {
  address = var.vault_addr
  token   = var.vault_token
}

module "kubernetes_auth" {
  source          = "../../modules/kubernetes-auth"
  kubernetes_host = var.k8s_host
  auth_path       = "kubernetes"
  roles = {
    "payment-api" = {
      service_accounts = ["payment-api-sa"]
      namespaces       = ["finance-dev"]
      policies         = ["payment-api-policy", "common-policy"]
      ttl              = 3600
      max_ttl          = 14400
    }
    "vault-rotation" = {
      service_accounts = ["vault-rotation-sa"]
      namespaces       = ["vault-system"]
      policies         = ["rotation-policy"]
      ttl              = 1800
      max_ttl          = 3600
    }
  }
}

module "dynamic_secrets" {
  source            = "../../modules/dynamic-secrets"
  environment       = "dev"
  db_host           = var.db_host
  db_name           = var.db_name
  db_admin_user     = var.db_admin_user
  db_admin_password = var.db_admin_password
  db_roles = [
    {
      name         = "payment-api-role"
      creation_sql = [
        "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA payment TO \"{{name}}\";"
      ]
      ttl     = 3600
      max_ttl = 14400
    }
  ]
}

module "policies" {
  source = "../../modules/policies"
  policies = {
    "payment-api-policy" = file("${path.module}/../../policies/payment-api-policy.hcl")
    "common-policy"      = file("${path.module}/../../policies/common-policy.hcl")
    "rotation-policy"    = file("${path.module}/../../policies/rotation-policy.hcl")
  }
}
