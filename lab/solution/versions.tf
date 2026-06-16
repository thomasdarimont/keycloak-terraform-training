terraform {
  required_version = ">= 1.15.0"

  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = ">= 5.8.0"
    }
  }

  backend "local" {
    path = "./terraform.tfstate"
  }
}