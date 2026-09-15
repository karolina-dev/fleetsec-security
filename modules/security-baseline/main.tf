terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_kms_key" "fleetsec" {
  description             = "FleetSec security encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "fleetsec" {
  name          = "alias/fleetsec-security"
  target_key_id = aws_kms_key.fleetsec.key_id
}

resource "aws_s3_bucket" "security_logs" {
  bucket = var.security_logs_bucket
}

resource "aws_s3_bucket_public_access_block" "security_logs" {
  bucket = aws_s3_bucket.security_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "security_logs" {
  bucket = aws_s3_bucket.security_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "security_logs" {
  bucket = aws_s3_bucket.security_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.fleetsec.arn
    }
  }
}

resource "aws_iam_policy" "fleetsec_security_readonly" {
  name        = "FleetSecSecurityReadOnly"
  description = "Minimum read-only permissions for security operations"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "cloudtrail:DescribeTrails",
          "cloudtrail:GetTrailStatus",
          "config:Get*",
          "config:Describe*",
          "guardduty:Get*",
          "guardduty:List*",
          "securityhub:Get*",
          "securityhub:Describe*",
          "securityhub:List*"
        ]

        Resource = "*"
      }
    ]
  })
}

resource "aws_secretsmanager_secret" "fleetsec_app" {
  name                    = "fleetsec/app"
  description             = "Secrets for the FleetSec application"
  kms_key_id              = aws_kms_key.fleetsec.arn
  recovery_window_in_days = 7
}

resource "aws_vpc" "fleetsec" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "fleetsec-vpc"
  }
}

resource "aws_security_group" "fleetsec" {
  name        = "fleetsec-security-group"
  description = "Restricted security group for FleetSec workloads"
  vpc_id      = aws_vpc.fleetsec.id

  ingress {
    description = "SSH from trusted administration network"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "HTTPS from trusted network"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    description = "Outbound HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "fleetsec-security-group"
  }
}

resource "aws_s3_bucket" "cloudtrail" {
  bucket = "${var.security_logs_bucket}-cloudtrail"
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.fleetsec.arn
    }
  }
}

resource "aws_cloudtrail" "fleetsec" {
  name                          = "fleetsec-audit"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.fleetsec.arn
}