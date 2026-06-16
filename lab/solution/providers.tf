provider "keycloak" {
  client_id     = "terraform"
  client_secret = var.terraform_client_secret
  url           = var.keycloak_url
}