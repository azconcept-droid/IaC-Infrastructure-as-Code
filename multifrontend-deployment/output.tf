output "cloudfront_distribution_id" {
  value = module.cloudfront.distribution_id
}

output "cloudfront_distribution_arn" {
  value = module.cloudfront.distribution_arn
}

output "cloudfront_distribution_domain" {
  value = module.cloudfront.distribution_domain
}

output "emarket_bucket_domain" {
  value = module.emarket.bucket_domain
}

output "emarket_bucket_name" {
  value = module.emarket.bucket_name
}

output "ncdf_bucket_domain" {
  value = module.ncdf.bucket_domain
}

output "ncdf_bucket_name" {
  value = module.ncdf.bucket_name
}

output "github_deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}

output "emarket_secret_name" {
  value = module.emarket.secret_name
}

output "emarket_secret_id" {
  value = module.emarket.secret_id
}

output "ncdf_secret_name" {
  value = module.ncdf.secret_name
}

output "ncdf_secret_id" {
  value = module.ncdf.secret_id
}
