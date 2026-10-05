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

variable "schedule" {
  description = "When the update runs (EventBridge Scheduler cron, time zone below)"
  type        = string
  default     = "cron(30 6 * * ? *)"
}

variable "database_url" {
  description = "Optional PostgreSQL connection string; empty = only store the files"
  type        = string
  default     = ""
  sensitive   = true
}
