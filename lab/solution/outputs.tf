output "realm" {
  value = keycloak_realm.workshop.realm
}

output "frontend_client_id" {
  value = keycloak_openid_client.spa_frontend.client_id
}