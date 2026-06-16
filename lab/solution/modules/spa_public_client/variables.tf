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