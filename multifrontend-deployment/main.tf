module "cloudfront" {
  source = "./cloudfront"

  aws_region = var.aws_region

  sites = {
    "emarket.com" = module.emarket.bucket_domain
    "ncdf.com"    = module.ncdf.bucket_domain
  }

  enable_waf = var.enable_waf
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
      values = [
        "repo:${var.github_org}/${var.emarket_github_repo}:environment:*",
        "repo:${var.github_org}/${var.ncdf_github_repo}:environment:*",
      ]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "frontend-deployment-${var.environment}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_assume_role.json

  tags = {
    Environment = var.environment
    Purpose     = "GitHub-CI-CD"
  }
}

module "emarket" {
  source = "./frontend-infra/emarket"

  aws_account_id              = var.aws_account_id
  aws_region                  = var.aws_region
  environment                 = var.environment
  project_name                = var.emarket_project_name
  bucket_name                 = var.emarket_bucket_name
  github_org                  = var.github_org
  github_repo                 = var.emarket_github_repo
  github_environment_names    = var.github_environment_names
  secret_name                 = var.emarket_secret_name
  secret_id                   = var.emarket_secret_id
  github_deploy_role_arn      = aws_iam_role.github_deploy.arn
  cloudfront_distribution_arn = module.cloudfront.distribution_arn
}

module "ncdf" {
  source = "./frontend-infra/ncdf"

  aws_account_id              = var.aws_account_id
  aws_region                  = var.aws_region
  environment                 = var.environment
  project_name                = var.ncdf_project_name
  bucket_name                 = var.ncdf_bucket_name
  github_org                  = var.github_org
  github_repo                 = var.ncdf_github_repo
  github_environment_names    = var.github_environment_names
  secret_name                 = var.ncdf_secret_name
  secret_id                   = var.ncdf_secret_id
  github_deploy_role_arn      = aws_iam_role.github_deploy.arn
  cloudfront_distribution_arn = module.cloudfront.distribution_arn
}

