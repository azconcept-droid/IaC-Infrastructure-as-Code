output "bucket_domain" {
  value = aws_s3_bucket.site.bucket_regional_domain_name
}

output "bucket_name" {
  value = aws_s3_bucket.site.bucket
}

output "secret_name" {
  value = aws_secretsmanager_secret.build_env.name
}

output "secret_id" {
  value = var.secret_id
}
