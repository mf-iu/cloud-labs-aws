# The outputs of base: network, bucket and roles. base stays until the end
# of the course; service is created and destroyed in the session.
data "terraform_remote_state" "base" {
  backend = "s3"
  config  = merge(var.backend, { key = "06-infrastructure-as-code/base/terraform.tfstate" })
}

locals {
  name = "${var.prefix}-${var.owner}"
  base = data.terraform_remote_state.base.outputs
}
