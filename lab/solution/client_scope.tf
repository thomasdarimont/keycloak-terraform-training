resource "keycloak_openid_client_scope" "acme" {
  realm_id               = keycloak_realm.workshop.id
  name                   = "acme"
  description            = "ACME custom claims"
  include_in_token_scope = true
}

# Map the user attribute "department" into a "department" claim.
resource "keycloak_openid_user_attribute_protocol_mapper" "department" {
  realm_id        = keycloak_realm.workshop.id
  client_scope_id = keycloak_openid_client_scope.acme.id
  name            = "department"

  user_attribute   = "department"
  claim_name       = "department"
  claim_value_type = "String"

  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

# Add the backend client to the access token audience (aud).
resource "keycloak_openid_audience_protocol_mapper" "acme_audience" {
  realm_id        = keycloak_realm.workshop.id
  client_scope_id = keycloak_openid_client_scope.acme.id
  name            = "audience-app-backend"

  included_client_audience = keycloak_openid_client.app_backend.client_id

  add_to_id_token     = false
  add_to_access_token = true
}