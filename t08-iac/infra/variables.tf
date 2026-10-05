# prefix, owner, suffix, region, placefinder_image and admin_cidrs are set
# by tools/tofu.sh from config.env

variable "prefix" {
  description = "Project prefix for all names"
  type        = string
}

variable "owner" {
  description = "Initials of the participant"
  type        = string
}

variable "suffix" {
  description = "Random suffix for globally unique names (.state/suffix)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "placefinder_image" {
  description = "Image repository of PlaceFinder without tag (PLACEFINDER_IMAGE in config.env)"
  type        = string
}

variable "image_tag" {
  description = "Image tag to deploy"
  type        = string
  default     = "t07"
}

variable "enable_database" {
  description = "Create the RDS PostgreSQL instance (costs money, delete it after the lab)"
  type        = bool
  default     = false
}

variable "admin_cidrs" {
  description = "Networks that may connect to the database; tools/tofu.sh sets your IP"
  type        = list(string)
  default     = []
}
