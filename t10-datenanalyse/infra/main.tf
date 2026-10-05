# Data lake for lab t10: GeoParquet in S3, queried with DuckDB and Athena

locals {
  name = "${var.prefix}-${var.owner}-t10"
  columns = {
    geonameid         = "int"
    name              = "string"
    asciiname         = "string"
    latitude          = "double"
    longitude         = "double"
    feature_code      = "string"
    country_code      = "string"
    admin1_code       = "string"
    population        = "bigint"
    timezone          = "string"
    modification_date = "date"
    geom              = "binary" # WKB, see export_geoparquet.py
  }
}

resource "aws_s3_bucket" "lake" {
  bucket        = "${local.name}-${var.suffix}-lake"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "lake" {
  bucket                  = aws_s3_bucket.lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Athena writes query results here; they expire after seven days
resource "aws_s3_bucket_lifecycle_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id

  rule {
    id     = "expire-athena-results"
    status = "Enabled"
    filter {
      prefix = "athena-results/"
    }
    expiration {
      days = 7
    }
  }
}

# Workgroup with a cost limit: a query may scan at most 1 GB
resource "aws_athena_workgroup" "lab" {
  name          = local.name
  force_destroy = true

  configuration {
    enforce_workgroup_configuration = true
    bytes_scanned_cutoff_per_query  = 1073741824

    result_configuration {
      output_location = "s3://${aws_s3_bucket.lake.bucket}/athena-results/"
    }
  }
}

resource "aws_glue_catalog_database" "lab" {
  name = replace(local.name, "-", "_")
}

# Table definition only (schema on read): the data stays in S3
resource "aws_glue_catalog_table" "places" {
  name          = "places"
  database_name = aws_glue_catalog_database.lab.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL       = "TRUE"
    classification = "parquet"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.lake.bucket}/places/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    dynamic "columns" {
      for_each = local.columns
      content {
        name = columns.key
        type = columns.value
      }
    }
  }
}
