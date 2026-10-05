# Object storage for raw data and map tiles, registry for the images

resource "aws_s3_bucket" "data" {
  bucket        = "${local.name}-${var.suffix}-t08-data"
  force_destroy = true # lab only: "tofu destroy" deletes the objects as well
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_ecr_repository" "placefinder" {
  name         = "${local.name}-t08-placefinder"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "placefinder" {
  repository = aws_ecr_repository.placefinder.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep five images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 5 }
      action       = { type = "expire" }
    }]
  })
}
