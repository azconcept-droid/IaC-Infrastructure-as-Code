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

  code = <<EOF
function handler(event) {
    var request = event.request;
    var host = request.headers.host.value;

    %{~ for domain, bucket in var.sites ~}
    if (host === "${domain}" || host === "www.${domain}") {
        request.origin = {
            s3: {
                domainName: "${bucket}",
                region: "${var.aws_region}",
                authMethod: "sigv4"
            }
        };
    }
    %{~ endfor ~}

    return request;
}
EOF
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

  # viewer_certificate {
  #   acm_certificate_arn = var.acm_certificate_arn
  #   ssl_support_method  = "sni-only"
  # }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1"
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }
}