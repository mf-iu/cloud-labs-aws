# Store these values as GitHub Actions variables of the repository
# (Settings > Secrets and variables > Actions > Variables).

output "AWS_ROLE_ARN" {
  value = aws_iam_role.deploy.arn
}

output "AWS_REGION" {
  value = var.region
}
