# Follow-along: configure Keycloak with Terraform from scratch

A hands-on, build-it-yourself example. You start with an **empty folder** and a fresh
Keycloak, and add one file at a time until you have a realm, two clients, a custom client
scope with OIDC protocol mappers, and an identity provider — all managed by Terraform.

**This folder:**

- `lab/student/` — **you build here**, following the steps below.
- `lab/solution/` — the completed reference, if you get stuck or want to diff.
- `scratch/` — temporary files and notes.
- `data/` — keycloak data
- `docker-compose.yml` — a throwaway Keycloak to configure.

> The examples use the `terraform` command; OpenTofu's `tofu` is a drop-in replacement that
> works identically.

**You will build, in order:**

1. Terraform configuration, state, and the provider (authenticating as a service-account
   client an admin creates)
2. A realm and a test user
3. Two clients (a confidential backend, a public SPA)
4. A custom client scope
5. OIDC protocol mappers on that scope
6. Assign the scope to the SPA
7. An OIDC identity provider (+ a mapper)
8. Reference existing Keycloak objects with `data`
9. Package a public SPA client as a reusable module
10. A custom browser login flow (split username / password)
11. Inspect state, see drift, clean up

> Convention: work in the **`lab/student/`** folder — create each file there as you reach its
> step, and run the `terraform` commands from inside it. Terraform loads every `*.tf` file
> in a directory, so file names are just for our own organisation.

---

## Step 0 — Start Keycloak

A minimal Keycloak 26.6.3 is provided via `docker-compose.yml` (dev mode, in-memory DB).

```bash
docker compose up -d
docker compose logs -f         # wait for "Running the server in development mode"
```

Open <http://localhost:18080> and log in as **admin / admin**. Leave it running.

> Dev mode keeps everything in memory: `docker compose down` wipes the realm, so you can
> restart the exercise from a clean slate any time.

> `docker compose` commands run from this folder. The `terraform` steps below
> run from the `lab/student/` folder (`cd lab/student`).

---

## Step 1 — Create the Terraform client, then configure Terraform

Terraform authenticates as a dedicated **service-account client** in the `master` realm —
not a human admin login. An admin creates this client **once**; everyone who runs Terraform
then just needs its secret. (Client authentication can use a secret, x509 client
certificates, or signed JWTs — we use a secret here.)

### 1a. Create the `terraform` client (one-time admin task)

Use either the admin console or `kcadm`.

**Admin console**

1. Switch to the **master** realm → **Clients** → **Create client**.
2. Client type **OpenID Connect**, Client ID **`terraform`** → Next.
3. **Client authentication: On**; **Service account roles: On**; Standard flow and Direct
   access grants **off** → Next → Save.
4. **Credentials** tab → copy the **Client secret** (or set your own).
5. **Service account roles** tab → **Assign role** → filter **by realm roles** → assign
   **`admin`**.

**`kcadm` (scriptable)** — run from the project root (where `docker-compose.yml` is). These
run *inside* the container, where Keycloak listens on `8080` (not the `18080` host port):

```bash
KCADM="docker compose exec keycloak /opt/keycloak/bin/kcadm.sh"

# log in as the bootstrap admin
$KCADM config credentials --server http://localhost:8080 --realm master \
  --user admin --password admin

# create a confidential client with a service account and a fixed secret
$KCADM create clients -r master \
  -s clientId=terraform -s enabled=true \
  -s serviceAccountsEnabled=true -s standardFlowEnabled=false -s publicClient=false \
  -s secret=terraform-secret-change-me

# grant the service account the master realm "admin" role
$KCADM add-roles -r master --uusername service-account-terraform --rolename admin
```

Verify: **master** → Clients → `terraform` → *Service account roles* lists `admin`.

### 1b. Configure Terraform — in the `lab/student/` folder

`cd lab/student`, then create three files.

**`versions.tf`** — pin versions and choose where state lives:

```hcl
terraform {
  required_version = ">= 1.15.0"

  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = ">= 5.8.0"
    }
  }

  backend "local" {
    path = "./terraform.tfstate"
  }
}
```

**`providers.tf`** — authenticate as the `terraform` client (`client_credentials`):

```hcl
provider "keycloak" {
  client_id     = "terraform"
  client_secret = var.terraform_client_secret
  url           = var.keycloak_url
}
```

**`variables.tf`**:

```hcl
variable "keycloak_url" {
  type    = string
  default = "http://localhost:18080"
}

variable "terraform_client_secret" {
  type      = string
  sensitive = true
  default   = "terraform-secret-change-me"
}

variable "idp_client_secret" {
  type      = string
  sensitive = true
  default   = "change-me"
}
```

**`terraform.tfvars`** — your local secret (git-ignored; don't commit):

```hcl
terraform_client_secret = "terraform-secret-change-me"
```

Or skip the file and pass it via an **environment variable** instead — Terraform reads
`TF_VAR_<name>` for each input variable. This keeps the secret out of any file, which is how
CI usually supplies it:

```bash
export TF_VAR_terraform_client_secret='terraform-secret-change-me'
terraform plan
```

Other ways to set the same variable: `-var 'terraform_client_secret=…'` or
`-var-file=secrets.tfvars` on the command line. Precedence, low → high:
variable `default` < `TF_VAR_*` env < `terraform.tfvars` < `*.auto.tfvars` <
`-var` / `-var-file`. (So a value in `terraform.tfvars` overrides the env var — set it in
only one place.)

Initialise:

```bash
terraform init
```

> **What just happened?** `init` read `required_providers`, downloaded the Keycloak
> provider from the registry, and pinned it in `.terraform.lock.hcl`. **State** (the
> mapping between your config and real Keycloak objects) is written to `./terraform.tfstate`.
> This mapping is the thing kcc doesn't have, and it's what makes `plan` and import work.

---

## Step 2 — Create the realm and a test user

**`realm.tf`**:

```hcl
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
```

**`user.tf`** — a user you can log in as right away (account console now, your apps later):

```hcl
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
```

Preview, then apply:

```bash
terraform plan        # + keycloak_realm.workshop  and  + keycloak_user.test
terraform apply       # type 'yes'
```

Verify: the admin console has a **workshop** realm (top-left realm switcher). Test the login
by opening the **account console** at
<http://localhost:18080/realms/workshop/account> and signing in as **testuser / test**.

> Read the plan symbols: `+` create, `~` update in place, `-` destroy. Always read the
> plan before approving.


> Note that ff you got an error like `Error: error initializing keycloak provider`
```
│ with provider["registry.terraform.io/keycloak/keycloak"],
│ on providers.tf line 1, in provider "keycloak":
│ 1: provider "keycloak" {
│
│ failed to perform initial login to Keycloak: error sending GET request to /admin/serverinfo: 403 Forbidden. Response body: {"error":"HTTP 403 Forbidden"}
```
> This means the `terraform` client doesn't have the master realm admin role. Please assign the role to the `terraform` client and try again.
---

## Step 3 — Create two clients

**`clients.tf`** — a confidential backend and a public SPA:

```hcl
# Confidential, machine-to-machine (service account; no browser login).
resource "keycloak_openid_client" "app_backend" {
  realm_id  = keycloak_realm.workshop.id
  client_id = "app-backend"
  name      = "Application Backend"

  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = true   # enables the client_credentials grant
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
```

```bash
terraform plan        # 2 clients to add
terraform apply
```

Verify: realm **workshop** → Clients shows `app-backend` and `spa-frontend`.

> Note how `realm_id = keycloak_realm.workshop.id` *references* the realm resource. That
> reference is how Terraform knows to create the realm first — it builds a dependency
> graph from these references.

Now create a new keycloak_openid_client named "keycloak-website" with the following values:

```
Resource name: `keycloak_website`
Client ID: `keycloak-website`
Client name: `Keycloak Website`
access_type: `PUBLIC`
standard_flow_enabled: `true`
root_url: `https://www.keycloak.org/app`
base_url: `/?url=http://localhost:18080&realm=workshop&client=keycloak-website`
valid_redirect_uris: `["/*"]`
web_origins: `["+"]`
pkce_code_challenge_method: `S256`
```

---

## Step 4 — Create a custom client scope

**`client_scope.tf`**:

```hcl
resource "keycloak_openid_client_scope" "acme" {
  realm_id               = keycloak_realm.workshop.id
  name                   = "acme"
  description            = "ACME custom claims"
  include_in_token_scope = true
}
```

```bash
terraform apply
```

Verify: realm → Client scopes → `acme`.

---

## Step 5 — Add OIDC protocol mappers to the scope

Append two mappers to **`client_scope.tf`**:

```hcl
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
```

```bash
terraform plan        # 2 mappers to add
terraform apply
```

Verify: Client scopes → `acme` → Mappers shows both.

---

## Step 6 — Assign the scope to the SPA

A client only emits a scope's claims if the scope is assigned. Append to **`clients.tf`**:

```hcl
# Manages the SPA's COMPLETE default-scope list.
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
```

```bash
terraform apply
```

Verify: Clients → `spa-frontend` → Client scopes lists `acme` as **Default**.

---

## Step 7 — Add an OIDC identity provider

**`identity_provider.tf`** (placeholder endpoints — point them at a real provider to use):

```hcl
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
```

```bash
terraform apply
```

Verify: realm → Identity providers → `ACME OIDC`, with a `department` mapper.

---

## Step 8 — Reference existing objects with `data`

Not everything in a realm is yours to manage. Keycloak creates objects on its own — default
roles, the `realm-management` client, built-in client scopes — and other teams or tools may
create more. A **data source** lets you *read* such an existing object and wire it into your
managed resources, **without taking ownership of it**.

Here we let the `app-backend` service account manage users, by referencing the
`realm-management` client that Keycloak auto-creates in every realm.

**`data.tf`**:

```hcl
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
```

```bash
terraform plan        # the data source is READ during refresh, before the diff
terraform apply
```

Verify: Clients → `app-backend` → *Service account roles* now lists `manage-users`.

> A `data` source **only reads** — it never creates, updates, or deletes. Terraform
> refreshes it on every `plan` to pick up current values, but the object stays outside your
> state. Other useful ones: `keycloak_realm`, `keycloak_role`, `keycloak_group`,
> `keycloak_openid_client_scope`.

---

## Step 9 — Package a client as a reusable module

Real configs don't repeat resource blocks — they wrap a pattern in a **module** and call it
with different inputs. Let's package "public SPA client with PKCE" once and reuse it for a
second app.

A module is just a folder of `.tf` files. Create `modules/spa_public_client/` with four:

**`modules/spa_public_client/variables.tf`**

```hcl
variable "realm_id" {
  type = string
}

variable "client_id" {
  type = string
}

variable "name" {
  type    = string
  default = ""
}

variable "root_url" {
  type    = string
  default = ""
}

variable "valid_redirect_uris" {
  type = list(string)
}

variable "web_origins" {
  type    = list(string)
  default = ["+"]
}

variable "default_scopes" {
  type    = list(string)
  default = []
}
```

**`modules/spa_public_client/main.tf`**

```hcl
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
```

**`modules/spa_public_client/outputs.tf`**

```hcl
output "client_id" {
  value = keycloak_openid_client.this.client_id
}

output "internal_id" {
  value = keycloak_openid_client.this.id
}
```

**`modules/spa_public_client/versions.tf`** — declare which provider the module uses.
Without this, Terraform assumes the default `hashicorp/keycloak` namespace (which doesn't
exist) and IntelliJ flags `Unknown resource "keycloak_openid_client"` — a child module does
**not** inherit the root's provider source:

```hcl
terraform {
  required_providers {
    keycloak = {
      source = "keycloak/keycloak"
    }
  }
}
```

Now use it to create a second SPA — back in `lab/student/`, add **`spa_admin.tf`**:

```hcl
module "admin_spa" {
  source = "./modules/spa_public_client"

  realm_id            = keycloak_realm.workshop.id
  client_id           = "admin-spa"
  name                = "Admin SPA"
  root_url            = "http://localhost:5174"
  valid_redirect_uris = ["http://localhost:5174/*"]
  default_scopes      = ["profile", "email", "roles", keycloak_openid_client_scope.acme.name]
}
```

Adding a module means re-running `init` so Terraform registers it:

```bash
terraform init        # registers the new local module
terraform plan        # + module.admin_spa.keycloak_openid_client.this (and its default scopes)
terraform apply
```

Verify: realm → Clients → `admin-spa` (public, PKCE on, `acme` as a default scope).

> A module groups resources behind `variable` inputs and `output`s; reuse it by calling it
> again with different inputs. Resources inside gain a `module.` prefix in their address
> (`module.admin_spa.keycloak_openid_client.this`) — reuse *and* namespacing.

---

## Step 10 — A custom browser login flow (split username / password)

Authentication flows are a tree: a top-level **flow** holds **executions** (authenticators)
and **subflows**. Let's build a browser flow that asks for the username first and the
password on a **separate** screen (Keycloak's "identity-first" login) — using the
`auth-username-form` and `auth-password-form` authenticators instead of the combined
`auth-username-password-form`.

The structure we want:

```
browser-2step                  (top-level flow)
├── Cookie          ALTERNATIVE   (auth-cookie)
└── forms           ALTERNATIVE   (subflow)
    ├── Username Form  REQUIRED   (auth-username-form)
    └── Password Form  REQUIRED   (auth-password-form)
```

**`auth_flow.tf`**:

```hcl
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
```

```bash
terraform apply
```

> **Order matters, and Terraform parallelises by default.** The `depends_on` lines force the
> executions to be created in sequence — Cookie before the subflow, Username before Password.
> Without them the steps can land in the wrong order. (The bfd `master` realm builds its
> custom 2FA browser flow exactly this way.)

Verify: sign out, then open
<http://localhost:18080/realms/workshop/account> — you now enter the **username**, click
**Next**, and land on a **separate password** screen. In the admin console,
Authentication → Flows shows `browser-2step` bound as the **browser** flow.

> ⚠️ Binding a broken flow can lock users out of the realm. This one is complete (a Cookie
> alternative plus a required username + password subflow), so login keeps working — and the
> `master`-realm admin can always fix a realm's flow binding if needed.

---

## Step 11 — Inspect state, see drift, clean up

**Outputs** — create **`outputs.tf`**:

```hcl
output "realm" {
  value = keycloak_realm.workshop.realm
}

output "frontend_client_id" {
  value = keycloak_openid_client.spa_frontend.client_id
}
```

```bash
terraform apply
terraform output                 # prints the outputs
terraform state list             # everything Terraform now manages
terraform state show keycloak_realm.workshop
```

**Drift demo** — in the admin console, change the workshop realm's *Display name*. Then:

```bash
terraform plan                   # Terraform detects the drift and offers to revert
terraform apply                  # puts it back to "Workshop Realm"
```

**Clean up:**

```bash
terraform destroy                # remove everything Terraform created
docker compose down              # stop & wipe Keycloak
```

