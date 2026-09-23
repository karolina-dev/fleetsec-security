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

provider "aws" {
  alias  = "dr"
  region = var.dr_region
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------
# KMS - Primary Region
# ---------------------------------------------------------

resource "aws_kms_key" "fleetsec" {
  description             = "FleetSec security encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "EnableAccountRootPermissions"
        Effect = "Allow"

        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }

        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudTrailToEncryptLogs"
        Effect = "Allow"

        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }

        Action = [
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]

        Resource = "*"

        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_kms_alias" "fleetsec" {
  name          = "alias/fleetsec-security"
  target_key_id = aws_kms_key.fleetsec.key_id
}

# ---------------------------------------------------------
# KMS - DR Region
# ---------------------------------------------------------

resource "aws_kms_key" "fleetsec_dr" {
  provider = aws.dr

  description             = "FleetSec DR security encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "EnableAccountRootPermissions"
        Effect = "Allow"

        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }

        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "fleetsec_dr" {
  provider      = aws.dr
  name          = "alias/fleetsec-security-dr"
  target_key_id = aws_kms_key.fleetsec_dr.key_id
}

# ---------------------------------------------------------
# S3 - Security Logs Primary
# ---------------------------------------------------------

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

resource "aws_s3_bucket_versioning" "security_logs" {
  bucket = aws_s3_bucket.security_logs.id

  versioning_configuration {
    status = "Enabled"
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

resource "aws_s3_bucket_logging" "security_logs" {
  bucket        = aws_s3_bucket.security_logs.id
  target_bucket = aws_s3_bucket.cloudtrail.id
  target_prefix = "access-logs/security-logs/"
}

# ---------------------------------------------------------
# S3 - Security Logs DR
# ---------------------------------------------------------

resource "aws_s3_bucket" "security_logs_dr" {
  provider = aws.dr

  bucket = "${var.security_logs_bucket}-dr"
}

resource "aws_s3_bucket_public_access_block" "security_logs_dr" {
  provider = aws.dr

  bucket = aws_s3_bucket.security_logs_dr.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "security_logs_dr" {
  provider = aws.dr

  bucket = aws_s3_bucket.security_logs_dr.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "security_logs_dr" {
  provider = aws.dr

  bucket = aws_s3_bucket.security_logs_dr.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "security_logs_dr" {
  provider = aws.dr

  bucket = aws_s3_bucket.security_logs_dr.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.fleetsec_dr.arn
    }
  }
}

resource "aws_s3_bucket_logging" "security_logs_dr" {
  provider = aws.dr

  bucket        = aws_s3_bucket.security_logs_dr.id
  target_bucket = aws_s3_bucket.cloudtrail_dr.id
  target_prefix = "access-logs/security-logs-dr/"
}

# ---------------------------------------------------------
# IAM - Security Read Only
# ---------------------------------------------------------

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

# ---------------------------------------------------------
# IAM - S3 Replication
# ---------------------------------------------------------

resource "aws_iam_role" "s3_replication" {
  name = "FleetSecS3ReplicationRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "s3.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3_replication" {
  name = "FleetSecS3ReplicationPolicy"
  role = aws_iam_role.s3_replication.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ListSourceBuckets"
        Effect = "Allow"

        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]

        Resource = [
          aws_s3_bucket.security_logs.arn,
          aws_s3_bucket.cloudtrail.arn
        ]
      },
      {
        Sid    = "ReadSourceObjects"
        Effect = "Allow"

        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]

        Resource = [
          "${aws_s3_bucket.security_logs.arn}/*",
          "${aws_s3_bucket.cloudtrail.arn}/*"
        ]
      },
      {
        Sid    = "ReplicateObjects"
        Effect = "Allow"

        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]

        Resource = [
          "${aws_s3_bucket.security_logs_dr.arn}/*",
          "${aws_s3_bucket.cloudtrail_dr.arn}/*"
        ]
      },
      {
        Sid    = "DecryptSourceObjects"
        Effect = "Allow"

        Action = [
          "kms:Decrypt"
        ]

        Resource = aws_kms_key.fleetsec.arn
      },
      {
        Sid    = "EncryptDestinationObjects"
        Effect = "Allow"

        Action = [
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]

        Resource = aws_kms_key.fleetsec_dr.arn
      }
    ]
  })
}

# ---------------------------------------------------------
# Secrets Manager
# ---------------------------------------------------------

resource "aws_secretsmanager_secret" "fleetsec_app" {
  name                    = "fleetsec/app"
  description             = "Secrets for the FleetSec application"
  kms_key_id              = aws_kms_key.fleetsec.arn
  recovery_window_in_days = 7
}

# ---------------------------------------------------------
# VPC
# ---------------------------------------------------------

resource "aws_vpc" "fleetsec" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "fleetsec-vpc"
  }
}

# ---------------------------------------------------------
# Security Group
# ---------------------------------------------------------

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

# ---------------------------------------------------------
# S3 - CloudTrail Primary
# ---------------------------------------------------------

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

resource "aws_s3_bucket_ownership_controls" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
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

# ---------------------------------------------------------
# S3 - CloudTrail DR
# ---------------------------------------------------------

resource "aws_s3_bucket" "cloudtrail_dr" {
  provider = aws.dr

  bucket = "${var.security_logs_bucket}-cloudtrail-dr"
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_dr" {
  provider = aws.dr

  bucket = aws_s3_bucket.cloudtrail_dr.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "cloudtrail_dr" {
  provider = aws.dr

  bucket = aws_s3_bucket.cloudtrail_dr.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail_dr" {
  provider = aws.dr

  bucket = aws_s3_bucket.cloudtrail_dr.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_dr" {
  provider = aws.dr

  bucket = aws_s3_bucket.cloudtrail_dr.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.fleetsec_dr.arn
    }
  }
}

# ---------------------------------------------------------
# S3 Replication - Security Logs
# ---------------------------------------------------------

resource "aws_s3_bucket_replication_configuration" "security_logs" {
  depends_on = [
    aws_s3_bucket_versioning.security_logs,
    aws_s3_bucket_versioning.security_logs_dr
  ]

  bucket = aws_s3_bucket.security_logs.id
  role   = aws_iam_role.s3_replication.arn

  rule {
    id     = "security-logs-dr"
    status = "Enabled"

    filter {
      prefix = ""
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    destination {
      bucket        = aws_s3_bucket.security_logs_dr.arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.fleetsec_dr.arn
      }
    }
  }
}

# ---------------------------------------------------------
# S3 Replication - CloudTrail
# ---------------------------------------------------------

resource "aws_s3_bucket_replication_configuration" "cloudtrail" {
  depends_on = [
    aws_s3_bucket_versioning.cloudtrail,
    aws_s3_bucket_versioning.cloudtrail_dr
  ]

  bucket = aws_s3_bucket.cloudtrail.id
  role   = aws_iam_role.s3_replication.arn

  rule {
    id     = "cloudtrail-dr"
    status = "Enabled"

    filter {
      prefix = ""
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    destination {
      bucket        = aws_s3_bucket.cloudtrail_dr.arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.fleetsec_dr.arn
      }
    }
  }
}

# ---------------------------------------------------------
# CloudWatch Logs
# ---------------------------------------------------------

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/fleetsec"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.fleetsec.arn
}

resource "aws_iam_role" "cloudtrail_to_cloudwatch" {
  name = "FleetSecCloudTrailCloudWatchRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "cloudtrail_to_cloudwatch" {
  name = "FleetSecCloudTrailCloudWatchPolicy"
  role = aws_iam_role.cloudtrail_to_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]

        Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
      }
    ]
  })
}

# ---------------------------------------------------------
# CloudTrail
# ---------------------------------------------------------

resource "aws_cloudtrail" "fleetsec" {
  name                          = "fleetsec-audit"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.fleetsec.arn

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_to_cloudwatch.arn

  depends_on = [
    aws_iam_role_policy.cloudtrail_to_cloudwatch
  ]
}