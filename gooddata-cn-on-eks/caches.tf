resource "random_id" "suffix" {
  byte_length = 8
}

resource "aws_s3_bucket" "exports" {
  bucket = "gooddata-cn-exports-${random_id.suffix.hex}"

  tags = local.tags
}

resource "aws_s3_bucket_lifecycle_configuration" "exports" {
  bucket = aws_s3_bucket.exports.id
  rule {
    id = "expire-old-exports"
    filter {}
    status = "Enabled"
    expiration {
      days = 2
    }
  }
  rule {
    id = "abort-old-multiparts"
    filter {}
    status = "Enabled"
    abort_incomplete_multipart_upload {
      days_after_initiation = 2
    }
  }
}

resource "aws_s3_bucket" "quiver" {
  bucket = "gooddata-cn-quiver-${random_id.suffix.hex}"

  tags = local.tags
}

resource "aws_s3_bucket_lifecycle_configuration" "quiver" {
  bucket = aws_s3_bucket.quiver.id
  rule {
    id = "abort-old-multiparts"
    filter {}
    status = "Enabled"
    abort_incomplete_multipart_upload {
      days_after_initiation = 2
    }
  }
}

resource "aws_iam_policy" "cache_policy" {
  name        = "${module.eks.cluster_name}-gooddata-cn"
  path        = "/"
  description = "Defines access to AWS resources for GoodData CN service account"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListObjects",
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.exports.arn}/*",
          "${aws_s3_bucket.quiver.arn}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.exports.arn}",
          "${aws_s3_bucket.quiver.arn}",
        ]
      },
    ]
  })
}

module "iam_eks_role_gooddata" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version   = "~> 5.39.1"
  role_name = "${module.eks.cluster_name}-gooddata-cn"

  role_policy_arns = {
    policy = aws_iam_policy.cache_policy.arn
  }

  oidc_providers = {
    eks = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${kubernetes_namespace.gooddata-cn.metadata.0.name}:gooddata-cn"]
    }
  }
}
