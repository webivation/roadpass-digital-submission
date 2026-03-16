# staging/terragrunt.hcl
#
# Instantiates the VPC module for the staging environment.
# Run from this directory:
#   terragrunt plan
#   terragrunt apply

include "root" {
  path   = find_in_parent_folders()
  expose = true
}

terraform {
  source = "../modules/vpc"
}

# ──────────────────────────────────────────────────────────
# Staging-specific inputs
# ──────────────────────────────────────────────────────────
inputs = {
  # Inherited from root:  project, region, environment = "staging"

  vpc_cidr = "172.16.0.0/16"

  # Two AZs in us-east-1
  availability_zones = ["us-east-1a", "us-east-1b"]

  # Four public subnets – 2 per AZ
  # AZ1: 172.16.1.0/24 and 172.16.2.0/24
  # AZ2: 172.16.3.0/24 and 172.16.4.0/24
  public_subnet_cidrs = [
    "172.16.1.0/24",
    "172.16.2.0/24",
    "172.16.3.0/24",
    "172.16.4.0/24",
  ]

  # Four private subnets – 2 per AZ
  # AZ1: 172.16.11.0/24 and 172.16.12.0/24
  # AZ2: 172.16.13.0/24 and 172.16.14.0/24
  private_subnet_cidrs = [
    "172.16.11.0/24",
    "172.16.12.0/24",
    "172.16.13.0/24",
    "172.16.14.0/24",
  ]

  tags = {
    CostCenter = "staging-infra"
  }
}
