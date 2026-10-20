# Object storage as in session 7 (t07-objektspeicher): private bucket with
# CORS for the map and lifecycle rules
resource "aws_s3_bucket" "data" {
  bucket        = "${local.name}-${var.suffix}-t08-data"
  force_destroy = true # lab only: "tofu destroy" deletes the objects as well
}

# New buckets block public access and encrypt with SSE-S3 anyway; written
# down here, the settings are visible and protected against drift
resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  cors_rule {
    allowed_origins = ["http://localhost:5173"]
    allowed_methods = ["GET", "HEAD"]
    allowed_headers = ["Range"]
    expose_headers  = ["ETag", "Content-Length", "Content-Range"]
    max_age_seconds = 3600
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    id     = "expire-raw-data"
    status = "Enabled"
    filter {
      prefix = "raw/"
    }
    expiration {
      days = 30
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}
