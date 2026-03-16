variable "environment" {
  description = "Environment name (e.g. staging, production)"
  type        = string
}

variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "region" {
  description = "AWS region where the VPC will be created"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "Supernet CIDR block for the VPC"
  type        = string
  default     = "172.16.0.0/16"
}

variable "availability_zones" {
  description = "List of exactly two availability zone names to use"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Exactly two availability zones must be provided."
  }
}

variable "public_subnet_cidrs" {
  description = <<-EOT
    List of four CIDR blocks for public subnets. The first two are placed in the
    first AZ and the second two in the second AZ (two public subnets per AZ).
  EOT
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == 4
    error_message = "Exactly four public subnet CIDRs must be provided (two per AZ)."
  }
}

variable "private_subnet_cidrs" {
  description = <<-EOT
    List of four CIDR blocks for private subnets. The first two are placed in the
    first AZ and the second two in the second AZ (two private subnets per AZ).
  EOT
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == 4
    error_message = "Exactly four private subnet CIDRs must be provided (two per AZ)."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
