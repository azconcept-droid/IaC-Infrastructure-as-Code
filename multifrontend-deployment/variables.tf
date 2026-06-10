variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
  default     = "956536811090"
}

variable "aws_region" {
  description = "AWS region for regional resources such as S3, IAM, and Secrets Manager."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment name. Expected values are staging or production."
  type        = string
  default     = "staging"

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production."
  }
}

variable "github_org" {
  description = "GitHub organization or user that owns the repository."
  type        = string
  default     = "azconcept-droid-org"
}

variable "github_environment_names" {
  description = "GitHub Environment names allowed to assume the deploy role. Defaults to the Terraform environment value."
  type        = list(string)
  default     = null
}

# Emarket frontend configuration
variable "emarket_project_name" {
  description = "Project name for emarket frontend."
  type        = string
  default     = "emarket-frontend"
}

variable "emarket_github_repo" {
  description = "GitHub repository name for emarket."
  type        = string
  default     = "emarket-frontend-vanilla"
}

variable "emarket_bucket_name" {
  description = "Optional S3 bucket name for emarket. Defaults to project-environment-account-region."
  type        = string
  default     = null
}

variable "emarket_secret_name" {
  description = "Secrets Manager secret name for emarket Vite build variables."
  type        = string
  default     = "emarket-frontend-vanilla-secrets"
}

variable "emarket_secret_id" {
  description = "Secrets Manager secret id for emarket Vite build variables."
  type        = string
  default     = null
}

# NCDF frontend configuration
variable "ncdf_project_name" {
  description = "Project name for ncdf frontend."
  type        = string
  default     = "ncdf-frontend"
}

variable "ncdf_github_repo" {
  description = "GitHub repository name for ncdf."
  type        = string
  default     = "ncdf-frontend-vanilla"
}

variable "ncdf_bucket_name" {
  description = "Optional S3 bucket name for ncdf. Defaults to project-environment-account-region."
  type        = string
  default     = null
}

variable "ncdf_secret_name" {
  description = "Secrets Manager secret name for ncdf Vite build variables."
  type        = string
  default     = "ncdf-frontend-vanilla-secrets"
}

variable "ncdf_secret_id" {
  description = "Secrets Manager secret id for ncdf Vite build variables."
  type        = string
  default     = null
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub Actions OIDC provider. Set false if the AWS account already has one."
  type        = bool
  default     = true
}

variable "github_oidc_provider_arn" {
  description = "Existing GitHub Actions OIDC provider ARN when create_github_oidc_provider is false."
  type        = string
  default     = null
}

variable "enable_waf" {
  description = "Enable AWS WAF for CloudFront distribution"
  type        = bool
  default     = false
}

variable "github_oidc_thumbprint" {
  description = "GitHub Actions OIDC root CA thumbprint."
  type        = string
  default     = "6938fd4d98bab03faadb97b34396831e3780aea1"
}
