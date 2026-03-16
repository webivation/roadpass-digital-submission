variable "project" {
  description = "Project name – used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. staging, production)"
  type        = string
}

variable "region" {
  description = "AWS region where resources are created"
  type        = string
  default     = "us-east-1"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "vpc_id" {
  description = "ID of the VPC in which to deploy the stack"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the Application Load Balancer (min 2 for multi-AZ)"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "At least two public subnets are required for ALB multi-AZ deployment."
  }
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the Auto Scaling Group (min 2 for multi-AZ)"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least two private subnets are required for ASG multi-AZ deployment."
  }
}

# ---------------------------------------------------------------------------
# EC2 / AMI
# ---------------------------------------------------------------------------

variable "ami_id" {
  description = "ID of the Packer-built AMI to use. Leave empty to use the latest Amazon Linux 2023 AMI."
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "EC2 instance type for the ASG instances"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Name of the EC2 key pair for SSH access. Leave empty to disable key-pair-based SSH."
  type        = string
  default     = ""
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 20
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks permitted to SSH into the EC2 instances"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

# ---------------------------------------------------------------------------
# Auto Scaling Group
# ---------------------------------------------------------------------------

variable "asg_desired_capacity" {
  description = "Desired number of EC2 instances in the Auto Scaling Group"
  type        = number
  default     = 2
}

variable "asg_min_size" {
  description = "Minimum number of EC2 instances in the Auto Scaling Group"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of EC2 instances in the Auto Scaling Group"
  type        = number
  default     = 4
}

# ---------------------------------------------------------------------------
# TLS (optional bonus)
# ---------------------------------------------------------------------------

variable "certificate_arn" {
  description = "ARN of an ACM certificate to enable HTTPS on the ALB. Leave empty to serve HTTP only."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Fry role – user-data variables injected into each EC2 instance at launch
# ---------------------------------------------------------------------------

variable "site_title" {
  description = "HTML <title> rendered by the fry role"
  type        = string
  default     = "Roadpass EC2 App"
}

variable "site_heading" {
  description = "Page heading rendered by the fry role"
  type        = string
  default     = "Welcome to Roadpass"
}

variable "site_body" {
  description = "Body text rendered by the fry role"
  type        = string
  default     = "This nginx server was built with Packer and Ansible."
}

# ---------------------------------------------------------------------------
# Tags
# ---------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags to merge onto all resources"
  type        = map(string)
  default     = {}
}
