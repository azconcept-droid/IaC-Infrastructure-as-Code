output "bucket_domain" {
  value = aws_s3_bucket.site.bucket_regional_domain_name
}

output "bucket_name" {
  value = aws_s3_bucket.site.bucket
}

output "github_oidc_provider_arn" {
  value       = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.github_oidc_provider_arn
  description = "ARN of the GitHub OIDC provider"
}
