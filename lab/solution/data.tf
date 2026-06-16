# Read an object Keycloak created for us. `data` looks it up; it does not manage it.
data "keycloak_openid_client" "realm_management" {
  realm_id  = keycloak_realm.workshop.id
  client_id = "realm-management"
}

# Grant the app-backend service account the realm-management "manage-users" role.
resource "keycloak_openid_client_service_account_role" "backend_manage_users" {
  realm_id                = keycloak_realm.workshop.id
  service_account_user_id = keycloak_openid_client.app_backend.service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management.id
  role                    = "manage-users"
}