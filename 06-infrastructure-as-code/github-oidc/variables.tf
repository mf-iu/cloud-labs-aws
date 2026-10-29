# prefix, owner, suffix and region are set by tools/tofu.sh from config.env

variable "prefix" {
  type = string
}

variable "owner" {
  type = string
}

variable "suffix" {
  type = string
}

variable "region" {
  type = string
}

variable "github_repository" {
  description = "Repository that may deploy, e.g. \"jdoe/placefinder\""
  type        = string
}

variable "github_branch" {
  description = "Only workflow runs on this branch get credentials"
  type        = string
  default     = "master"
}

variable "create_oidc_provider" {
  description = "false if the account already has the GitHub OIDC provider"
  type        = bool
  default     = true
}
