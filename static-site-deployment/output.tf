output "cloudfront_distribution_id" {
  value = module.cloudfront.distribution_id
}

output "cloudfront_distribution_arn" {
  value = module.cloudfront.distribution_arn
}

output "cloudfront_distribution_domain" {
  value = module.cloudfront.distribution_domain
}

output "bucket_domain" {
  value = module.site.bucket_domain
}

output "bucket_name" {
  value = module.site.bucket_name
}

output "github_deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}
