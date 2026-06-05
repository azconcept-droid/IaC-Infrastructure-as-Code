module "cloudfront" {
  source = "./cloudfront"

  aws_region = var.aws_region

  sites = {
    "emarket.com" = module.emarket.bucket_domain
    "ncdf.com" = module.ncdf.bucket_domain
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
  create_github_oidc_provider = var.create_github_oidc_provider
  github_oidc_provider_arn    = var.github_oidc_provider_arn
  github_oidc_thumbprint      = var.github_oidc_thumbprint
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
  create_github_oidc_provider = false
  github_oidc_provider_arn    = var.github_oidc_provider_arn != null ? var.github_oidc_provider_arn : module.emarket.github_oidc_provider_arn
  github_oidc_thumbprint      = var.github_oidc_thumbprint
  cloudfront_distribution_arn = module.cloudfront.distribution_arn
}
