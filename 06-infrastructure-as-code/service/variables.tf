# prefix, owner, region, placefinder_image and backend are set by
# tools/tofu.sh from config.env and .state/backend.hcl

variable "prefix" {
  description = "Project prefix for all names"
  type        = string
}

variable "owner" {
  description = "Initials of the participant"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "backend" {
  description = "Settings of the S3 backend, to read the outputs of base"
  type        = map(string)
}

variable "placefinder_image" {
  description = "Image repository of PlaceFinder without tag (PLACEFINDER_IMAGE in config.env)"
  type        = string
}

variable "image_tag" {
  description = "Image tag to deploy first; the pipeline deploys later versions"
  type        = string
  default     = "t08"
}

variable "enable_database" {
  description = "Create PostgreSQL in the database subnets (costs money, destroy it after the lab)"
  type        = bool
  default     = false
}

variable "max_tasks" {
  description = "Upper limit for the number of PlaceFinder tasks"
  type        = number
  default     = 2
}
