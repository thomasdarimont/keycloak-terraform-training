resource "keycloak_oidc_identity_provider" "acme_oidc" {
  realm        = keycloak_realm.workshop.id
  alias        = "acme-oidc"
  display_name = "ACME OIDC"
  enabled      = true

  authorization_url = "https://idp.example.com/authorize"
  token_url         = "https://idp.example.com/token"
  user_info_url     = "https://idp.example.com/userinfo"
  jwks_url          = "https://idp.example.com/jwks"
  issuer            = "https://idp.example.com"

  client_id     = "workshop-keycloak"
  client_secret = var.idp_client_secret

  default_scopes = "openid profile email"
  sync_mode      = "IMPORT"

  # Keys without a first-class argument go in extra_config.
  extra_config = {
    clientAuthMethod = "client_secret_post"
  }
}

# Import the upstream "department" claim into the local user attribute.
resource "keycloak_attribute_importer_identity_provider_mapper" "acme_department" {
  realm                   = keycloak_realm.workshop.id
  identity_provider_alias = keycloak_oidc_identity_provider.acme_oidc.alias
  name                    = "department"
  claim_name              = "department"
  user_attribute          = "department"

  extra_config = {
    syncMode = "INHERIT"
  }
}