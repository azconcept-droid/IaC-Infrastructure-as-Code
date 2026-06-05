# Root-level variables passed from parent module
variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "aws_region" {
  description = "AWS region for regional resources such as S3, IAM, and Secrets Manager."
  type        = string
}

variable "environment" {
  description = "Deployment environment name. Expected values are staging or production."
  type        = string
}

variable "project_name" {
  description = "Short project name used when naming AWS resources."
  type        = string
}

variable "bucket_name" {
  description = "Optional globally unique S3 bucket name. Defaults to project-environment-account-region."
  type        = string
}

variable "github_org" {
  description = "GitHub organization or user that owns the repository."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
}

variable "github_environment_names" {
  description = "GitHub Environment names allowed to assume the deploy role. Defaults to the Terraform environment value."
  type        = list(string)
}

variable "secret_name" {
  description = "Optional Secrets Manager secret name for Vite build variables."
  type        = string
}

variable "secret_id" {
  description = "Optional Secrets Manager secret id for Vite build variables."
  type        = string
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub Actions OIDC provider. Set false if the AWS account already has one."
  type        = bool
}

variable "github_oidc_provider_arn" {
  description = "Existing GitHub Actions OIDC provider ARN when create_github_oidc_provider is false."
  type        = string
}

variable "github_oidc_thumbprint" {
  description = "GitHub Actions OIDC root CA thumbprint."
  type        = string
}

# Module-specific variable
variable "cloudfront_distribution_arn" {
  description = "CloudFront shared distribution ARN."
  type        = string
}
