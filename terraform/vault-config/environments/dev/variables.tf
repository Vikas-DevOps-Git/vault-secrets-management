variable "vault_addr"        { type = string  default = "http://localhost:8200" }
variable "vault_token"       { type = string  sensitive = true }
variable "k8s_host"          { type = string  default = "https://kubernetes.default.svc" }
variable "db_host"           { type = string }
variable "db_name"           { type = string  default = "financedb" }
variable "db_admin_user"     { type = string }
variable "db_admin_password" { type = string  sensitive = true }
