terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.69"
    }
  }

  # Remote state in S3, a state of its own next to t08-iac/infra
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
