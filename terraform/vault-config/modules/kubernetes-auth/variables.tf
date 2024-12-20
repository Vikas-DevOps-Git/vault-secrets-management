variable "auth_path"        { type = string  default = "kubernetes" }
variable "kubernetes_host"  { type = string }
variable "kubernetes_ca_cert" { type = string default = "" }
variable "token_issuer"     { type = string  default = "" }

variable "roles" {
  type = map(object({
    service_accounts = list(string)
    namespaces       = list(string)
    policies         = list(string)
    ttl              = number
    max_ttl          = number
  }))
  default = {}
}
