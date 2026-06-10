resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "shared-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_cache_policy" "host_cache" {
  name = "host-cache-policy"

  parameters_in_cache_key_and_forwarded_to_origin {
    headers_config {
      header_behavior = "whitelist"
      headers { items = ["Host"] }
    }

    cookies_config { cookie_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
  }
}

resource "aws_cloudfront_function" "router" {
  name    = "host-router"
  runtime = "cloudfront-js-1.0"
  publish = true

  code = templatefile("${path.module}/cloudfront-function.js", {
    sites      = var.sites
    aws_region = var.aws_region
  })

  lifecycle {
    create_before_destroy = true
  }
}

# WAF Web ACL for CloudFront
resource "aws_wafv2_web_acl" "this" {
  count       = var.enable_waf ? 1 : 0
  name        = var.waf_name
  description = var.waf_description
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Block specific HTTP methods
  dynamic "rule" {
    for_each = length(var.block_http_methods) > 0 ? [1] : []
    content {
      name     = "BlockHttpMethods"
      priority = 0

      statement {
        or_statement {
          dynamic "statement" {
            for_each = var.block_http_methods
            content {
              byte_match_statement {
                positional_constraint = "EXACTLY"
                search_string         = statement.value
                field_to_match {
                  method {}
                }
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
      }

      action {
        block {}
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name               = "BlockHttpMethods"
        sampled_requests_enabled  = true
      }
    }
  }

  # Rate limiting rule
  dynamic "rule" {
    for_each = var.enable_rate_limiting ? [1] : []
    content {
      name     = "RateLimitRule"
      priority = 1

      statement {
        rate_based_statement {
          limit              = var.rate_limit_threshold
          aggregate_key_type = "IP"
        }
      }

      action {
        block {}
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name               = "RateLimitRule"
        sampled_requests_enabled  = true
      }
    }
  }

  # AWS Managed Rules - Common Rule Set
  dynamic "rule" {
    for_each = var.enable_common_rule_group ? [1] : []
    content {
      name     = "AWSManagedRulesCommonRuleSet"
      priority = 2

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesCommonRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name               = "AWSManagedRulesCommonRuleSet"
        sampled_requests_enabled  = true
      }
    }
  }

  # AWS Managed Rules - Known Bad Inputs
  dynamic "rule" {
    for_each = var.enable_known_bad_inputs_rule_group ? [1] : []
    content {
      name     = "AWSManagedRulesKnownBadInputsRuleSet"
      priority = 3

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesKnownBadInputsRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name               = "AWSManagedRulesKnownBadInputsRuleSet"
        sampled_requests_enabled  = true
      }
    }
  }

  # AWS Managed Rules - SQL Injection
  dynamic "rule" {
    for_each = var.enable_sql_injection_rule_group ? [1] : []
    content {
      name     = "AWSManagedRulesSQLiRuleSet"
      priority = 4

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesSQLiRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name               = "AWSManagedRulesSQLiRuleSet"
        sampled_requests_enabled  = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name               = var.waf_name
    sampled_requests_enabled  = true
  }

  tags = merge(
    {
      Name = var.waf_name
    },
    var.waf_tags
  )
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  default_root_object = "index.html"
  is_ipv6_enabled     = true

  dynamic "origin" {
    for_each = var.sites
    content {
      domain_name              = origin.value
      origin_id                = "origin-${origin.key}"
      origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
    }
  }

  default_cache_behavior {
    target_origin_id       = "origin-${keys(var.sites)[0]}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id = aws_cloudfront_cache_policy.host_cache.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.router.arn
    }
  }

  # Attach WAF if enabled
  web_acl_id = var.enable_waf ? aws_wafv2_web_acl.this[0].arn : ""

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1"
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }
}