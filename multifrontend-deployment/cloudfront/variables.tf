# Root-level variables passed from parent module
variable "aws_region" {
  description = "AWS region"
  type        = string
}

# CloudFront-specific variable
variable "sites" {
  description = "Map of domain => bucket domain"
  type        = map(string)
}
