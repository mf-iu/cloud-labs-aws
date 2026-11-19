# The bucket of base: the function writes the change files there under
# geonames/. This configuration adds only the function and its schedule.
data "terraform_remote_state" "base" {
  backend = "s3"
  config  = merge(var.backend, { key = "06-infrastructure-as-code/base/terraform.tfstate" })
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

locals {
  name   = "${var.prefix}-${var.owner}-t09"
  bucket = data.terraform_remote_state.base.outputs.bucket
}
