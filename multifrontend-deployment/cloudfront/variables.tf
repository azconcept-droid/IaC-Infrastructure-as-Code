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

# WAF Configuration
variable "enable_waf" {
  description = "Enable AWS WAF for CloudFront distribution"
  type        = bool
  default     = false
}

variable "waf_name" {
  description = "Name for the WAF Web ACL"
  type        = string
  default     = "frontend-waf"
}

variable "waf_description" {
  description = "Description for the WAF Web ACL"
  type        = string
  default     = "WAF for frontend CloudFront distribution"
}

variable "block_http_methods" {
  description = "HTTP methods to block (e.g., POST, PUT, DELETE, PATCH)"
  type        = list(string)
  default     = ["POST", "PUT", "DELETE", "PATCH"]
}

variable "enable_rate_limiting" {
  description = "Enable rate limiting rule"
  type        = bool
  default     = true
}

variable "rate_limit_threshold" {
  description = "Number of requests from a single IP address that are allowed in a five-minute period"
  type        = number
  default     = 2000
}

variable "enable_common_rule_group" {
  description = "Enable AWSManagedRulesCommonRuleSet"
  type        = bool
  default     = true
}

variable "enable_known_bad_inputs_rule_group" {
  description = "Enable AWSManagedRulesKnownBadInputsRuleSet"
  type        = bool
  default     = true
}

variable "enable_sql_injection_rule_group" {
  description = "Enable AWSManagedRulesSQLiRuleSet"
  type        = bool
  default     = true
}

variable "waf_tags" {
  description = "Tags to apply to WAF resources"
  type        = map(string)
  default     = {}
}
