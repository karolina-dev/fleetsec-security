variable "aws_region" {
  description = "AWS primary region"
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "AWS disaster recovery region for S3 replication"
  type        = string
  default     = "us-west-2"
}

variable "security_logs_bucket" {
  description = "Bucket for centralized security logs"
  type        = string
  default     = "fleetsec-security-logs-example"
}

variable "admin_cidr" {
  description = "Trusted administration network CIDR"
  type        = string
  default     = "10.0.0.0/16"
}