variable "policies" {
  type        = map(string)
  description = "Map of policy name to HCL policy document"
  default     = {}
}
