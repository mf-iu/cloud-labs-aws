# Set by tools/tofu.sh from config.env and .state/backend.hcl

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

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

variable "backend" {
  description = "Settings of the S3 backend, to read the outputs of base"
  type        = map(string)
}
