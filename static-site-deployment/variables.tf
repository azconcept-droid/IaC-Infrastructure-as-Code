variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "aws_region" {
  description = "AWS region for regional resources such as S3, IAM, and CloudFront WAF. CloudFront WAF must be created in eu-west-1."
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Deployment environment name. Expected values are testing or production."
  type        = string
  default     = "testing"

  validation {
    condition     = contains(["testing", "production"], var.environment)
    error_message = "environment must be testing or production."
  }
}

variable "github_org" {
  description = "GitHub organization or user that owns the repository."
  type        = string
  default     = "your-github-org"
}

variable "github_repo" {
  description = "GitHub repository name for the static site."
  type        = string
  default     = "static-site"
}

variable "github_environment_names" {
  description = "GitHub Environment names allowed to assume the deploy role. Defaults to the Terraform environment value."
  type        = list(string)
  default     = null
}

variable "project_name" {
  description = "Short project name used when naming AWS resources."
  type        = string
  default     = "static-site"
}

variable "bucket_name" {
  description = "Optional globally unique S3 bucket name. Defaults to project-environment-account-region."
  type        = string
  default     = null
}

variable "site_domain" {
  description = "Placeholder domain for the site. It is used for tagging/commenting only; no custom certificate or alias is attached."
  type        = string
  default     = "static-site.example.com"
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub Actions OIDC provider. Set false if the AWS account already has one."
  type        = bool
  default     = false
}

variable "github_oidc_provider_arn" {
  description = "Existing GitHub Actions OIDC provider ARN when create_github_oidc_provider is false."
  type        = string
  default     = null
}

variable "github_oidc_thumbprint" {
  description = "GitHub Actions OIDC root CA thumbprint."
  type        = string
  default     = "6938fd4d98bab03faadb97b34396831e3780aea1"
}

variable "enable_waf" {
  description = "Enable AWS WAF for the CloudFront distribution. Disable for a pure cache-timing test to avoid extra cost and request noise."
  type        = bool
}

variable "min_ttl" {
  description = "Minimum CloudFront cache TTL in seconds. Keep 0 so origin Cache-Control headers are respected."
  type        = number
  default     = 0

  validation {
    condition     = var.min_ttl >= 0
    error_message = "min_ttl must be greater than or equal to 0."
  }
}

variable "default_ttl" {
  description = "Default CloudFront cache TTL in seconds when the origin sends no Cache-Control/Expires header."
  type        = number
  default     = 86400

  validation {
    condition     = var.default_ttl >= 0
    error_message = "default_ttl must be greater than or equal to 0."
  }
}

variable "max_ttl" {
  description = "Maximum CloudFront cache TTL in seconds."
  type        = number
  default     = 31536000

  validation {
    condition     = var.max_ttl >= 0
    error_message = "max_ttl must be greater than or equal to 0."
  }
}

variable "github_org_id" {
  type    = string
  default = "1234567"
}

variable "github_repo_id" {
  type    = string
  default = "1234567890"
}

