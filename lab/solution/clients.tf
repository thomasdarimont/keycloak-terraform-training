# Confidential, machine-to-machine (service account; no browser login).
resource "keycloak_openid_client" "app_backend" {
  realm_id  = keycloak_realm.workshop.id
  client_id = "app-backend"
  name      = "Application Backend"

  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = true # enables the client_credentials grant
}

# Public Single-Page-App using Authorization Code + PKCE.
resource "keycloak_openid_client" "spa_frontend" {
  realm_id  = keycloak_realm.workshop.id
  client_id = "spa-frontend"
  name      = "SPA Frontend"

  access_type           = "PUBLIC"
  standard_flow_enabled = true

  root_url            = "http://localhost:5173"
  valid_redirect_uris = ["http://localhost:5173/*"]
  web_origins         = ["+"]

  pkce_code_challenge_method = "S256"
}

resource "keycloak_openid_client_default_scopes" "spa_frontend" {
  realm_id  = keycloak_realm.workshop.id
  client_id = keycloak_openid_client.spa_frontend.id

  default_scopes = [
    "profile",
    "email",
    "roles",
    keycloak_openid_client_scope.acme.name,
  ]
}

# Keycloak Website test app using Authorization Code + PKCE.
resource "keycloak_openid_client" "keycloak_website" {
  realm_id  = keycloak_realm.workshop.id
  client_id = "keycloak-website"
  name      = "Keycloak Website"

  access_type           = "PUBLIC"
  standard_flow_enabled = true

  root_url            = "https://www.keycloak.org/app"
  base_url            = "/?url=http://localhost:18080&realm=workshop&client=keycloak-website"
  valid_redirect_uris = ["/*"]
  web_origins         = ["+"]

  pkce_code_challenge_method = "S256"
}
