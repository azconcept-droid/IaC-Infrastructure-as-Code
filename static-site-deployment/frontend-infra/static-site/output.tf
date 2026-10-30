output "bucket_domain" {
  value = aws_s3_bucket.site.bucket_regional_domain_name
}

output "bucket_name" {
  value = aws_s3_bucket.site.bucket
}
