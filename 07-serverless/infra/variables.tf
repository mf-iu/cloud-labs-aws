# prefix, owner, suffix, region and backend are set by tools/tofu.sh from
# config.env and .state/backend.hcl

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

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

variable "schedule" {
  description = "When the update runs (EventBridge Scheduler cron, time zone Europe/Berlin)"
  type        = string
  default     = "cron(30 6 * * ? *)"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

variable "database_url" {
  description = "Optional PostgreSQL connection string; empty = only store the files (extra task)"
  type        = string
  default     = ""
  sensitive   = true
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

variable "dead_letter" {
  description = "Extra task: dead-letter queue for failed runs, with an alarm"
  type        = bool
  default     = false
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

variable "alert_email" {
  description = "Extra task: e-mail address for the alarm; empty = alarm without notification"
  type        = string
  default     = ""
}
