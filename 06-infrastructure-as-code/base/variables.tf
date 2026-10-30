# prefix, owner, suffix and region are set by tools/tofu.sh from config.env

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

variable "prefix" {
  description = "Project prefix for all names"
  type        = string
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

variable "owner" {
  description = "Initials of the participant"
  type        = string
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

variable "suffix" {
  description = "Random suffix for globally unique names (.state/suffix)"
  type        = string
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

variable "region" {
  description = "AWS region"
  type        = string
}
