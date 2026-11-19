output "athena_workgroup" {
  value = aws_athena_workgroup.lab.name
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

output "glue_database" {
  value = aws_glue_catalog_database.lab.name
}
