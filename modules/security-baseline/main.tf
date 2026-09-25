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

  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

provider "aws" {
  alias  = "dr"
  region = var.dr_region

  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

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
          AWS = "arn:aws:iam::${var.aws_account_id}:root"
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
            "aws:SourceAccount" = var.aws_account_id
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
          AWS = "arn:aws:iam::${var.aws_account_id}:root"
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
  bucket              = var.security_logs_bucket
  object_lock_enabled = true
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

# ---------------------------------------------------------
# S3 - Security Logs Lifecycle and Object Lock
# ---------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "security_logs" {
  bucket = aws_s3_bucket.security_logs.id

  rule {
    id     = "archive-security-logs"
    status = "Enabled"

    filter {}

    transition {
      days          = 180
      storage_class = "GLACIER"
    }
  }
}

resource "aws_s3_bucket_object_lock_configuration" "security_logs" {
  bucket = aws_s3_bucket.security_logs.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 365
    }
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
# IAM - Account Password Policy
# ---------------------------------------------------------

resource "aws_iam_account_password_policy" "fleetsec" {
  minimum_password_length        = 14
  password_reuse_prevention      = 24
  max_password_age               = 90
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
}

# ---------------------------------------------------------
# IAM - ECS Application Role
# ---------------------------------------------------------

resource "aws_iam_role" "ecs_task" {
  name = "FleetSecECSTaskRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "FleetSecECSTaskRole"
    Tier = "application"
  }
}

resource "aws_iam_role_policy" "ecs_task" {
  name = "FleetSecECSTaskLeastPrivilege"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ReadApplicationSecret"
        Effect = "Allow"

        Action = [
          "secretsmanager:GetSecretValue"
        ]

        Resource = aws_secretsmanager_secret.fleetsec_app.arn
      },
      {
        Sid    = "DecryptApplicationSecret"
        Effect = "Allow"

        Action = [
          "kms:Decrypt"
        ]

        Resource = aws_kms_key.fleetsec.arn
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
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "fleetsec-vpc"
  }
}

# ---------------------------------------------------------
# VPC Flow Logs - S3 + CloudWatch
# ---------------------------------------------------------

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/flow-logs/fleetsec"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.fleetsec.arn
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "FleetSecVPCFlowLogsRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "FleetSecVPCFlowLogsPolicy"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]

        Resource = "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
      }
    ]
  })
}

resource "aws_flow_log" "fleetsec_cloudwatch" {
  vpc_id                   = aws_vpc.fleetsec.id
  traffic_type             = "ALL"
  max_aggregation_interval = 60

  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs.arn
  iam_role_arn         = aws_iam_role.vpc_flow_logs.arn

  tags = {
    Name = "fleetsec-vpc-flow-logs-cloudwatch"
  }
}

resource "aws_flow_log" "fleetsec_s3" {
  vpc_id                   = aws_vpc.fleetsec.id
  traffic_type             = "ALL"
  max_aggregation_interval = 60

  log_destination_type = "s3"
  log_destination      = "${aws_s3_bucket.security_logs.arn}/vpc-flow-logs/"

  tags = {
    Name = "fleetsec-vpc-flow-logs-s3"
  }
}

# ---------------------------------------------------------
# VPC - Subnets: Public / App / Data across 2 AZs
# ---------------------------------------------------------

resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.fleetsec.id
  availability_zone       = var.availability_zones[count.index]
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "fleetsec-public-${count.index + 1}"
    Tier = "public"
  }
}

resource "aws_subnet" "app" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.fleetsec.id
  availability_zone       = var.availability_zones[count.index]
  cidr_block              = var.app_subnet_cidrs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "fleetsec-app-${count.index + 1}"
    Tier = "app"
  }
}

resource "aws_subnet" "data" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.fleetsec.id
  availability_zone       = var.availability_zones[count.index]
  cidr_block              = var.data_subnet_cidrs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "fleetsec-data-${count.index + 1}"
    Tier = "data"
  }
}

resource "aws_internet_gateway" "fleetsec" {
  vpc_id = aws_vpc.fleetsec.id

  tags = {
    Name = "fleetsec-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.fleetsec.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.fleetsec.id
  }

  tags = {
    Name = "fleetsec-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------
# Network ACL - Restricted Data Layer
# ---------------------------------------------------------

resource "aws_network_acl" "data" {
  vpc_id = aws_vpc.fleetsec.id

  tags = {
    Name = "fleetsec-data-nacl"
    Tier = "data"
  }
}

resource "aws_network_acl_rule" "data_ingress_postgres" {
  count = length(var.app_subnet_cidrs)

  network_acl_id = aws_network_acl.data.id
  rule_number    = 100 + count.index
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.app_subnet_cidrs[count.index]
  from_port      = 5432
  to_port        = 5432
}

resource "aws_network_acl_rule" "data_egress_ephemeral" {
  count = length(var.app_subnet_cidrs)

  network_acl_id = aws_network_acl.data.id
  rule_number    = 200 + count.index
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.app_subnet_cidrs[count.index]
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_association" "data" {
  count = length(var.availability_zones)

  network_acl_id = aws_network_acl.data.id
  subnet_id      = aws_subnet.data[count.index].id
}

resource "aws_route_table" "app" {
  vpc_id = aws_vpc.fleetsec.id

  tags = {
    Name = "fleetsec-app-rt"
  }
}

resource "aws_route_table_association" "app" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app.id
}

resource "aws_route_table" "data" {
  vpc_id = aws_vpc.fleetsec.id

  tags = {
    Name = "fleetsec-data-rt"
  }
}

resource "aws_route_table_association" "data" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}

# ---------------------------------------------------------
# RDS - PostgreSQL Secure Database
# ---------------------------------------------------------

resource "aws_security_group" "rds" {
  name        = "fleetsec-rds-sg"
  description = "Allow PostgreSQL only from FleetSec app subnets"
  vpc_id      = aws_vpc.fleetsec.id

  dynamic "ingress" {
    for_each = var.app_subnet_cidrs

    content {
      description = "PostgreSQL from app subnet"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    description = "HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "fleetsec-rds-sg"
    Tier = "data"
  }
}

resource "aws_db_subnet_group" "fleetsec" {
  name       = "fleetsec-db-subnet-group"
  subnet_ids = aws_subnet.data[*].id

  tags = {
    Name = "fleetsec-db-subnet-group"
  }
}

resource "aws_db_parameter_group" "fleetsec" {
  name   = "fleetsec-postgres16"
  family = "postgres16"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  tags = {
    Name = "fleetsec-postgres16"
  }
}

resource "aws_db_instance" "fleetsec" {
  identifier = "fleetsec-postgres"

  engine         = "postgres"
  engine_version = "16"

  instance_class        = "db.t3.micro"
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  db_name  = "fleetsec"
  username = "fleetsec_admin"

  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.fleetsec.arn

  multi_az            = true
  publicly_accessible = false

  storage_encrypted = true
  kms_key_id        = aws_kms_key.fleetsec.arn

  backup_retention_period = 7
  copy_tags_to_snapshot   = true

  db_subnet_group_name   = aws_db_subnet_group.fleetsec.name
  parameter_group_name   = aws_db_parameter_group.fleetsec.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  deletion_protection = true
  skip_final_snapshot = true

  tags = {
    Name = "fleetsec-postgres"
    Tier = "data"
  }
}

resource "aws_secretsmanager_secret_rotation" "fleetsec_rds" {
  secret_id          = aws_db_instance.fleetsec.master_user_secret[0].secret_arn
  rotate_immediately = false

  rotation_rules {
    automatically_after_days = 30
  }

  depends_on = [
    aws_db_instance.fleetsec
  ]
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
# AWS Config
# ---------------------------------------------------------

resource "aws_iam_role" "config" {
  name = "FleetSecAWSConfigRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "config.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_configuration_recorder" "fleetsec" {
  name     = "fleetsec-config"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.config
  ]
}

resource "aws_config_delivery_channel" "fleetsec" {
  name           = "fleetsec-config"
  s3_bucket_name = aws_s3_bucket.security_logs.id

  depends_on = [
    aws_config_configuration_recorder.fleetsec
  ]
}

# ---------------------------------------------------------
# Amazon GuardDuty
# ---------------------------------------------------------

resource "aws_guardduty_detector" "fleetsec" {
  enable = true

  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = {
    Name = "fleetsec-guardduty"
  }
}

# ---------------------------------------------------------
# AWS Security Hub
# ---------------------------------------------------------

resource "aws_securityhub_account" "fleetsec" {
  enable_default_standards = true

  depends_on = [
    aws_guardduty_detector.fleetsec
  ]
}

# ---------------------------------------------------------
# AWS WAF
# ---------------------------------------------------------

resource "aws_wafv2_web_acl" "fleetsec" {
  name        = "fleetsec-waf"
  description = "FleetSec regional web application firewall"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

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
      metric_name                = "fleetsec-waf-common"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "fleetsec-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "fleetsec-waf"
  }
}


resource "aws_config_configuration_recorder_status" "fleetsec" {
  name       = aws_config_configuration_recorder.fleetsec.name
  is_enabled = true

  depends_on = [
    aws_config_delivery_channel.fleetsec
  ]
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
# ---------------------------------------------------------
# CloudTrail - Metric Filters + CloudWatch Alarms
# ---------------------------------------------------------

resource "aws_cloudwatch_log_metric_filter" "root_console_login" {
  name           = "fleetsec-root-console-login"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name

  pattern = <<PATTERN
{ ($.eventName = "ConsoleLogin") && ($.userIdentity.type = "Root") && ($.responseElements.ConsoleLogin = "Success") }
PATTERN

  metric_transformation {
    name      = "FleetSecRootConsoleLogin"
    namespace = "FleetSec/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "root_console_login" {
  alarm_name          = "fleetsec-root-console-login"
  alarm_description   = "Detecta inicio de sesión exitoso de la cuenta root."
  namespace           = "FleetSec/Security"
  metric_name         = "FleetSecRootConsoleLogin"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_log_metric_filter" "iam_changes" {
  name           = "fleetsec-iam-changes"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name

  pattern = <<PATTERN
{ ($.eventName = "CreateUser") || ($.eventName = "DeleteUser") || ($.eventName = "CreateRole") || ($.eventName = "DeleteRole") || ($.eventName = "AttachRolePolicy") || ($.eventName = "DetachRolePolicy") || ($.eventName = "PutRolePolicy") || ($.eventName = "DeleteRolePolicy") || ($.eventName = "CreatePolicy") || ($.eventName = "DeletePolicy") || ($.eventName = "UpdateAssumeRolePolicy") || ($.eventName = "AddUserToGroup") || ($.eventName = "RemoveUserFromGroup") }
PATTERN

  metric_transformation {
    name      = "FleetSecIAMChanges"
    namespace = "FleetSec/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "iam_changes" {
  alarm_name          = "fleetsec-iam-changes"
  alarm_description   = "Detecta cambios relevantes en IAM."
  namespace           = "FleetSec/Security"
  metric_name         = "FleetSecIAMChanges"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_log_metric_filter" "security_group_changes" {
  name           = "fleetsec-security-group-changes"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name

  pattern = <<PATTERN
{ ($.eventName = "AuthorizeSecurityGroupIngress") || ($.eventName = "AuthorizeSecurityGroupEgress") || ($.eventName = "RevokeSecurityGroupIngress") || ($.eventName = "RevokeSecurityGroupEgress") || ($.eventName = "CreateSecurityGroup") || ($.eventName = "DeleteSecurityGroup") || ($.eventName = "UpdateSecurityGroupRuleDescriptionsIngress") || ($.eventName = "UpdateSecurityGroupRuleDescriptionsEgress") }
PATTERN

  metric_transformation {
    name      = "FleetSecSecurityGroupChanges"
    namespace = "FleetSec/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "security_group_changes" {
  alarm_name          = "fleetsec-security-group-changes"
  alarm_description   = "Detecta cambios en Security Groups."
  namespace           = "FleetSec/Security"
  metric_name         = "FleetSecSecurityGroupChanges"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_log_metric_filter" "disable_key_rotation" {
  name           = "fleetsec-disable-key-rotation"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name

  pattern = <<PATTERN
{ $.eventName = "DisableKeyRotation" }
PATTERN

  metric_transformation {
    name      = "FleetSecDisableKeyRotation"
    namespace = "FleetSec/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "disable_key_rotation" {
  alarm_name          = "fleetsec-disable-key-rotation"
  alarm_description   = "Detecta intentos de deshabilitar la rotación de claves KMS."
  namespace           = "FleetSec/Security"
  metric_name         = "FleetSecDisableKeyRotation"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
}
