resource "keycloak_authentication_flow" "browser_2step" {
  realm_id    = keycloak_realm.workshop.id
  alias       = "browser-2step"
  description = "Browser flow with separate username and password steps"
}

# Re-use an existing session if present.
resource "keycloak_authentication_execution" "cookie" {
  realm_id          = keycloak_realm.workshop.id
  parent_flow_alias = keycloak_authentication_flow.browser_2step.alias
  authenticator     = "auth-cookie"
  requirement       = "ALTERNATIVE"
}

# Subflow holding the two form steps.
resource "keycloak_authentication_subflow" "forms" {
  realm_id          = keycloak_realm.workshop.id
  parent_flow_alias = keycloak_authentication_flow.browser_2step.alias
  alias             = "forms-2step"
  provider_id       = "basic-flow"
  requirement       = "ALTERNATIVE"

  depends_on = [keycloak_authentication_execution.cookie]
}

# Step 1 — ask for the username only.
resource "keycloak_authentication_execution" "username_form" {
  realm_id          = keycloak_realm.workshop.id
  parent_flow_alias = keycloak_authentication_subflow.forms.alias
  authenticator     = "auth-username-form"
  requirement       = "REQUIRED"
}

# Step 2 — ask for the password on a separate screen.
resource "keycloak_authentication_execution" "password_form" {
  realm_id          = keycloak_realm.workshop.id
  parent_flow_alias = keycloak_authentication_subflow.forms.alias
  authenticator     = "auth-password-form"
  requirement       = "REQUIRED"

  depends_on = [keycloak_authentication_execution.username_form]
}

# Make this the realm's browser flow.
resource "keycloak_authentication_bindings" "browser" {
  realm_id     = keycloak_realm.workshop.id
  browser_flow = keycloak_authentication_flow.browser_2step.alias
}