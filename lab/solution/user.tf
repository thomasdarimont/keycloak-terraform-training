resource "keycloak_user" "test" {
  realm_id       = keycloak_realm.workshop.id
  username       = "testuser"
  enabled        = true
  email          = "testuser@example.com"
  email_verified = true
  first_name     = "Test"
  last_name      = "User"

  initial_password {
    value     = "test"
    temporary = false
  }
}