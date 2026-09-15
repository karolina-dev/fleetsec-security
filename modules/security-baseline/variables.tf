variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
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