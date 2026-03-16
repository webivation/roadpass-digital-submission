# Staging-specific Packer variable overrides
# Usage: packer build -var-file=vars/staging.pkrvars.hcl nginx-ami.pkr.hcl

region              = "us-east-1"
instance_type       = "t3.micro"
ami_name_prefix     = "roadpass-nginx"
environment         = "staging"
project             = "roadpass"
associate_public_ip = true

# Set these to use a specific VPC/subnet for the build instance.
# Leave as empty strings to use the default VPC.
vpc_id    = ""
subnet_id = ""
