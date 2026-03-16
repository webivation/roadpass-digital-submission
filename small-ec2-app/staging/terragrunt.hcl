# staging/terragrunt.hcl – small-ec2-app
#
# Instantiates the ec2-app module for the staging environment.
# Run from this directory:
#   terragrunt plan
#   terragrunt apply

include "root" {
  path   = find_in_parent_folders()
  expose = true
}

terraform {
  source = "../modules/ec2-app"
}

dependency "vpc" {
  config_path = "../../aws-vpc-exercise/staging"
}

# ──────────────────────────────────────────────────────────
# Staging-specific inputs
# ──────────────────────────────────────────────────────────
inputs = {
  # Inherited from root:  project = "roadpass", region = "us-east-1", environment = "staging"

  # ── Networking ─────────────────────────────────────────────────────────────
  # Consume VPC and subnet IDs directly from aws-vpc-exercise staging outputs.
  vpc_id             = dependency.vpc.outputs.vpc_id
  public_subnet_ids  = dependency.vpc.outputs.public_subnet_ids
  private_subnet_ids = dependency.vpc.outputs.private_subnet_ids

  # ── EC2 / AMI ──────────────────────────────────────────────────────────────
  # Set ami_id to the AMI produced by Packer (from packer/manifest.json).
  # Leave empty to fall back to the latest Amazon Linux 2023 AMI.
  ami_id        = ""
  instance_type = "t3.micro"

  # SSH key pair name (must exist in the target region).
  # Leave empty to disable key-pair-based SSH and rely on SSM Session Manager.
  key_name = ""

  # CIDR blocks allowed to SSH into instances (defaults to RFC-1918 private space)
  ssh_allowed_cidrs = ["10.0.0.0/8"]

  # ── Auto Scaling Group ─────────────────────────────────────────────────────
  asg_desired_capacity = 2
  asg_min_size         = 2
  asg_max_size         = 4

  # ── TLS / ACM (optional bonus) ─────────────────────────────────────────────
  # Set to a valid ACM certificate ARN to enable HTTPS on the ALB.
  # The certificate must cover the domain pointing to the ALB.
  certificate_arn = ""

  # ── Fry role – user-data variables ─────────────────────────────────────────
  site_title   = "Roadpass – Staging"
  site_heading = "Welcome to Roadpass Staging"
  site_body    = "This nginx server was baked with Packer, configured with Ansible, and deployed via Terraform."

  # ── Tags ───────────────────────────────────────────────────────────────────
  tags = {
    CostCenter = "staging-infra"
  }
}
