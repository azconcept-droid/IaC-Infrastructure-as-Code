# Root-level variables passed from parent module
variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "aws_region" {
  description = "AWS region for regional resources such as S3 and IAM."
  type        = string
}

variable "environment" {
  description = "Deployment environment name. Expected values are testing or production."
  type        = string
}

variable "project_name" {
  description = "Short project name used when naming AWS resources."
  type        = string
}

variable "bucket_name" {
  description = "Optional globally unique S3 bucket name. Defaults to project-environment-account-region."
  type        = string
  default     = null
}

variable "github_org" {
  description = "GitHub organization or user that owns the repository."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
}

variable "github_deploy_role_arn" {
  description = "ARN of the shared GitHub deployment IAM role."
  type        = string
}

variable "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN."
  type        = string
}
