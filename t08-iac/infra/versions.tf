terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.69"
    }
  }

  # Remote state in S3; bucket, region and key come from tools/tofu.sh
  # (.state/backend.hcl, written by t08-iac/bootstrap-state.sh)
  backend "s3" {}
}

provider "aws" {
  region = var.region

  # Every resource gets these tags (find leftovers: tools/find-leftovers.sh)
  default_tags {
    tags = {
      course = "cloud-computing"
      lab    = "t08"
    }
  }
}
