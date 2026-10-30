module "cloudfront" {
  source = "./cloudfront"

  environment   = var.environment
  project_name  = var.project_name
  site_domain   = var.site_domain
  bucket_domain = module.site.bucket_domain

  enable_waf  = var.enable_waf
  min_ttl     = var.min_ttl
  default_ttl = var.default_ttl
  max_ttl     = var.max_ttl
}

# Shared GitHub OIDC Provider and IAM Role
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [var.github_oidc_thumbprint]

  tags = {
    Name = "github-oidc-provider"
  }
}

locals {
  github_oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.github_oidc_provider_arn
  github_environment_names = var.github_environment_names != null ? var.github_environment_names : [var.environment]
  github_subject_claims = [
    for name in local.github_environment_names :
    "repo:${var.github_org}@${var.github_org_id}/${var.github_repo}@${var.github_repo_id}:environment:${name}"
  ]
}

data "aws_iam_policy_document" "github_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_subject_claims
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.project_name}-${var.environment}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_assume_role.json

  lifecycle {
    precondition {
      condition     = var.create_github_oidc_provider || var.github_oidc_provider_arn != null
      error_message = "Set github_oidc_provider_arn when create_github_oidc_provider is false."
    }
  }

  tags = {
    Environment = var.environment
    Purpose     = "GitHub-CI-CD"
  }
}

module "site" {
  source = "./frontend-infra/static-site"

  aws_account_id           = var.aws_account_id
  aws_region               = var.aws_region
  environment              = var.environment
  project_name             = var.project_name
  bucket_name              = var.bucket_name
  github_org               = var.github_org
  github_repo              = var.github_repo
  github_deploy_role_arn   = aws_iam_role.github_deploy.arn

  cloudfront_distribution_arn = module.cloudfront.distribution_arn
}
