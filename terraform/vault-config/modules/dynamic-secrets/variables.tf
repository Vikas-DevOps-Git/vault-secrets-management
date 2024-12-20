variable "environment"      { type = string }
variable "db_host"          { type = string }
variable "db_port"          { type = number  default = 5432 }
variable "db_name"          { type = string }
variable "db_admin_user"    { type = string }
variable "db_admin_password"{ type = string  sensitive = true }

variable "db_roles" {
  type = list(object({
    name         = string
    creation_sql = list(string)
    ttl          = number
    max_ttl      = number
  }))
  default = []
}
