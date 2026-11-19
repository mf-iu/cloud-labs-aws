# Extra task of session 10: serverless SQL with Amazon Athena on the
# GeoParquet file in the bucket of base. Athena charges per data read; the
# workgroup stops every query that would read more than 1 GB.

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Columns of places.parquet (cloud-labs-local/10-analytics/export_geoparquet.py)
# as Hive types; the table is only a description, the data stay in the bucket
# (schema on read). The geometry column geom is left out: latitude and
# longitude are in the file as plain numbers for engines like this one.
locals {
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
  }
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Athena writes every result as a file into S3. A bucket of its own: it goes
# with "destroy", and the results expire after a day.
resource "aws_s3_bucket" "results" {
  bucket        = "${local.name}-${var.suffix}-athena"
  force_destroy = true # lab only: "tofu destroy" deletes the objects as well
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

resource "aws_s3_bucket_public_access_block" "results" {
  bucket                  = aws_s3_bucket.results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

resource "aws_s3_bucket_lifecycle_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    id     = "expire-results"
    status = "Enabled"
    filter {}
    expiration {
      days = 1
    }
  }
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Workgroup with a cost limit: a query may read at most 1 GB
resource "aws_athena_workgroup" "lab" {
  name          = local.name
  force_destroy = true

  configuration {
    enforce_workgroup_configuration = true
    bytes_scanned_cutoff_per_query  = 1073741824

    result_configuration {
      output_location = "s3://${aws_s3_bucket.results.bucket}/"
    }
  }
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

resource "aws_glue_catalog_database" "lab" {
  name = replace(local.name, "-", "_")
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Table definition in the Glue Data Catalog: where the files are and which
# columns they have
resource "aws_glue_catalog_table" "places" {
  name          = "places"
  database_name = aws_glue_catalog_database.lab.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL       = "TRUE"
    classification = "parquet"
  }

  storage_descriptor {
    location      = "s3://${local.bucket}/places/"
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
