resource "keycloak_realm" "workshop" {
  realm        = "workshop"
  enabled      = true
  display_name = "Workshop Realm"

  # Token lifespans are DURATION STRINGS ("5m", "300s") — not bare integers.
  access_token_lifespan = "5m"

  registration_allowed     = false
  reset_password_allowed   = true
  login_with_email_allowed = true
}