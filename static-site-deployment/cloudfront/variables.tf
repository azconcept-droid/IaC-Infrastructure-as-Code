variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "project_name" {
  description = "Short project name used when naming AWS resources."
  type        = string
}

variable "site_domain" {
  description = "Placeholder domain used for tagging and documentation."
  type        = string
}

variable "bucket_domain" {
  description = "Regional domain name of the S3 bucket that hosts the static site."
  type        = string
}

# Cache TTL configuration
variable "min_ttl" {
  description = "Minimum CloudFront cache TTL in seconds."
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

# WAF Configuration
variable "enable_waf" {
  description = "Enable AWS WAF for the CloudFront distribution."
  type        = bool
  default     = false
}

variable "waf_name" {
  description = "Optional explicit name for the WAF Web ACL. Defaults to project-environment-waf."
  type        = string
  default     = null
}

variable "waf_description" {
  description = "Description for the WAF Web ACL."
  type        = string
  default     = "WAF for static site CloudFront distribution"
}

variable "block_http_methods" {
  description = "HTTP methods to block (e.g., POST, PUT, DELETE, PATCH)."
  type        = list(string)
  default     = ["POST", "PUT", "DELETE", "PATCH"]
}

variable "enable_rate_limiting" {
  description = "Enable rate limiting rule."
  type        = bool
  default     = true
}

variable "rate_limit_threshold" {
  description = "Number of requests from a single IP address that are allowed in a five-minute period."
  type        = number
  default     = 2000
}

variable "enable_common_rule_group" {
  description = "Enable AWSManagedRulesCommonRuleSet."
  type        = bool
  default     = true
}

variable "enable_known_bad_inputs_rule_group" {
  description = "Enable AWSManagedRulesKnownBadInputsRuleSet."
  type        = bool
  default     = true
}

variable "enable_sql_injection_rule_group" {
  description = "Enable AWSManagedRulesSQLiRuleSet."
  type        = bool
  default     = true
}

variable "waf_tags" {
  description = "Tags to apply to WAF resources."
  type        = map(string)
  default     = {}
}
