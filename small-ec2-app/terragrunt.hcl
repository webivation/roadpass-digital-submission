# Root terragrunt.hcl – small-ec2-app
#
# This file is the entry-point for all environments managed by Terragrunt.
# Child configurations (e.g. staging/terragrunt.hcl) include this file to
# inherit provider generation, remote state, and common inputs.

locals {
  # Parse the environment name from the directory path:
  # …/small-ec2-app/<environment>/terragrunt.hcl  →  <environment>
  stack_path  = path_relative_to_include()
  path_parts  = split("/", local.stack_path)
  environment = local.path_parts[0]

  project = "roadpass"
  region  = "us-east-1"
}

# ──────────────────────────────────────────────────────────
# Remote State (S3 + DynamoDB)
# ──────────────────────────────────────────────────────────
remote_state {
  backend = "s3"

  config = {
    bucket         = "${local.project}-terraform-state-${local.environment}"
    key            = "small-ec2-app/${local.stack_path}/terraform.tfstate"
    region         = local.region
    encrypt        = true
    dynamodb_table = "${local.project}-terraform-locks-${local.environment}"
  }

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# ──────────────────────────────────────────────────────────
# AWS Provider Generation
# ──────────────────────────────────────────────────────────
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-EOF
    provider "aws" {
      region = "${local.region}"

      default_tags {
        tags = {
          Environment = "${local.environment}"
          Project     = "${local.project}"
          ManagedBy   = "terraform"
        }
      }
    }
  EOF
}

# ──────────────────────────────────────────────────────────
# Common Inputs (available to all child configurations)
# ──────────────────────────────────────────────────────────
inputs = {
  project     = local.project
  region      = local.region
  environment = local.environment
}
