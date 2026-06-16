resource "keycloak_openid_client" "this" {
  realm_id  = var.realm_id
  client_id = var.client_id
  name      = var.name

  access_type           = "PUBLIC"
  standard_flow_enabled = true

  root_url            = var.root_url
  valid_redirect_uris = var.valid_redirect_uris
  web_origins         = var.web_origins

  pkce_code_challenge_method = "S256"
}

resource "keycloak_openid_client_default_scopes" "this" {
  count     = length(var.default_scopes) > 0 ? 1 : 0
  realm_id  = var.realm_id
  client_id = keycloak_openid_client.this.id

  default_scopes = var.default_scopes
}