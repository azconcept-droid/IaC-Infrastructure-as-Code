data "aws_caller_identity" "current" {}

locals {
  bucket_name = coalesce(
    var.bucket_name,
    "${var.project_name}-${var.environment}-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  )

  secret_name = var.secret_name

  secret_id_arn = (
    var.secret_id == null ? null :
    startswith(var.secret_id, "arn:") ? var.secret_id :
    "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.secret_id}-*"
  )

  github_environment_subjects = [
    for environment_name in coalesce(var.github_environment_names, [var.environment]) :
    "repo:${var.github_org}/${var.github_repo}:environment:${environment_name}"
  ]
}

# ------------------------
# S3
# ------------------------

resource "aws_s3_bucket" "site" {
  bucket        = local.bucket_name
  force_destroy = true

  tags = {
    Name        = local.bucket_name
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ------------------------
# BUCKET POLICY (UPDATED)
# ------------------------

data "aws_iam_policy_document" "site_bucket" {
  statement {
    sid     = "AllowCloudFrontRead"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [var.cloudfront_distribution_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket     = aws_s3_bucket.site.id
  policy     = data.aws_iam_policy_document.site_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.site]
}

# ------------------------
# SECRETS
# ------------------------

resource "aws_secretsmanager_secret" "build_env" {
  name                    = local.secret_name
  recovery_window_in_days = 0

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# ------------------------
# GitHub Deployment Policy
data "aws_iam_policy_document" "github_deploy" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["*"]
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.site.arn]
  }

  statement {
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]
  }

  statement {
    actions = ["cloudfront:CreateInvalidation"]
    resources = [var.cloudfront_distribution_arn]
  }
}

resource "aws_iam_policy" "github_deploy" {
  name_prefix = "${var.project_name}-${var.environment}-deploy-"
  policy      = data.aws_iam_policy_document.github_deploy.json

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "github_deploy" {
  role       = split("/", var.github_deploy_role_arn)[1]
  policy_arn = aws_iam_policy.github_deploy.arn
}
