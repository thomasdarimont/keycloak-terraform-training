variable "keycloak_url" {
  type    = string
  default = "http://localhost:18080"
}

variable "terraform_client_secret" {
  type      = string
  sensitive = true
  default   = "terraform-secret-change-me"
}

variable "idp_client_secret" {
  type      = string
  sensitive = true
  default   = "change-me"
}