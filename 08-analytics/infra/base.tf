# The bucket of base: places.parquet lies there under places/
# (08-analytics/upload.sh). This configuration adds only what Athena needs.
data "terraform_remote_state" "base" {
  backend = "s3"
  config  = merge(var.backend, { key = "06-infrastructure-as-code/base/terraform.tfstate" })
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

locals {
  name   = "${var.prefix}-${var.owner}-t10"
  bucket = data.terraform_remote_state.base.outputs.bucket
}
