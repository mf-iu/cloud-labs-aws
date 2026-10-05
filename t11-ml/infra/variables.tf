# prefix, owner, suffix, region and placefinder_image are set by
# tools/tofu.sh from config.env

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

variable "placefinder_image" {
  description = "Image repository of PlaceFinder without tag"
  type        = string
}

variable "image_tag" {
  description = "Image with the /estimate endpoint"
  type        = string
  default     = "t11"
}

variable "model_key" {
  description = "Object key of the trained model in the bucket"
  type        = string
  default     = "models/estimate/model.joblib"
}
