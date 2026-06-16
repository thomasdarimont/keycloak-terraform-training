module "admin_spa" {
  source = "./modules/spa_public_client"

  realm_id            = keycloak_realm.workshop.id
  client_id           = "admin-spa"
  name                = "Admin SPA"
  root_url            = "http://localhost:5174"
  valid_redirect_uris = ["http://localhost:5174/*"]
  default_scopes      = ["profile", "email", "roles", keycloak_openid_client_scope.acme.name]
}