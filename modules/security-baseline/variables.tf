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

variable "vpc_cidr" {
  description = "CIDR for the FleetSec VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability Zones for the FleetSec VPC"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "app_subnet_cidrs" {
  description = "Application subnet CIDRs"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "data_subnet_cidrs" {
  description = "Data subnet CIDRs"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

variable "aws_account_id" {
  description = "Placeholder AWS account ID for offline Terraform plan"
  type        = string
  default     = "123456789012"
}