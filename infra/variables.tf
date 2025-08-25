variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI/SDK profile to use"
  type        = string
  default     = "default"
}

variable "project" {
  description = "Project prefix for names"
  type        = string
  default     = "rag-demo"
}

variable "owner" {
  description = "Owner tag"
  type        = string
  default     = "rx-user"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_password" {
  description = "Master DB password"
  type        = string
  sensitive   = true
}

variable "api_image" {
  description = "ECR image URI for FastAPI service"
  type        = string
}

variable "ui_image" {
  description = "ECR image URI for Streamlit service"
  type        = string
}

variable "app_env_vars" {
  description = "Environment variables common to both services"
  type        = map(string)
  default     = {}
}

variable "raw_bucket" { type = string }
variable "clean_bucket" { type = string }

