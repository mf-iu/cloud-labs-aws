# Keyless deployment from GitHub Actions: the workflow exchanges its OIDC
# token for short-lived AWS credentials of the role below (no access keys).

locals {
  name   = "${var.prefix}-${var.owner}"
  issuer = "token.actions.githubusercontent.com"
}

data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://${local.issuer}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://${local.issuer}"
}

locals {
  provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Only this repository and branch, not forks or pull requests
    condition {
      test     = "StringEquals"
      variable = "${local.issuer}:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "${local.name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

# Least privilege: roll out new images on the Express Mode services, nothing
# else. The images come from ghcr.io, so no registry permissions are needed.
data "aws_iam_policy_document" "deploy" {
  statement {
    sid = "UpdateExpressService"
    actions = [
      "ecs:DescribeExpressGatewayService", "ecs:UpdateExpressGatewayService",
      "ecs:ListServiceDeployments", "ecs:DescribeServiceDeployments",
    ]
    resources = ["*"]
  }
  # A new image means a new task definition with the roles of t08-iac/infra
  statement {
    sid       = "PassTaskRoles"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.name}-t08-ecs-*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}
