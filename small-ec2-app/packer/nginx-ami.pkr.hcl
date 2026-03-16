packer {
  required_version = ">= 1.9.0"

  required_plugins {
    amazon = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "region" {
  description = "AWS region to build the AMI in"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type used during AMI build"
  type        = string
  default     = "t3.micro"
}

variable "ami_name_prefix" {
  description = "Prefix for the resulting AMI name"
  type        = string
  default     = "roadpass-nginx"
}

variable "environment" {
  description = "Environment tag (e.g. staging, production)"
  type        = string
  default     = "staging"
}

variable "project" {
  description = "Project tag"
  type        = string
  default     = "roadpass"
}

variable "vpc_id" {
  description = "VPC ID for the build instance (leave empty to use default VPC)"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Subnet ID for the build instance (leave empty to use default subnet)"
  type        = string
  default     = ""
}

variable "associate_public_ip" {
  description = "Whether to associate a public IP with the build instance"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Data sources – find the latest Amazon Linux 2023 AMI
# ---------------------------------------------------------------------------

data "amazon-ami" "amazon_linux_2023" {
  region = var.region

  filters = {
    name                = "al2023-ami-2023.*-x86_64"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
    state               = "available"
  }

  owners      = ["amazon"]
  most_recent = true
}

# ---------------------------------------------------------------------------
# Build source
# ---------------------------------------------------------------------------

source "amazon-ebs" "nginx" {
  region        = var.region
  instance_type = var.instance_type

  # Use the latest Amazon Linux 2023 AMI as the base
  source_ami = data.amazon-ami.amazon_linux_2023.id

  # SSH communication
  communicator  = "ssh"
  ssh_username  = "ec2-user"
  ssh_interface = "public_ip"

  # Networking – fall back to default VPC/subnet when variables are empty
  vpc_id    = var.vpc_id != "" ? var.vpc_id : null
  subnet_id = var.subnet_id != "" ? var.subnet_id : null

  associate_public_ip_address = var.associate_public_ip

  # Resulting AMI configuration
  ami_name        = "${var.ami_name_prefix}-${var.environment}-{{timestamp}}"
  ami_description = "Amazon Linux 2023 with nginx – built by Packer for ${var.project}/${var.environment}"

  # Encrypt root volume
  encrypt_boot = true

  # Root volume configuration
  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # Tags applied to the resulting AMI and its snapshot
  tags = {
    Name        = "${var.ami_name_prefix}-${var.environment}"
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "packer"
    OS          = "Amazon Linux 2023"
    Service     = "nginx"
    BaseAMI     = data.amazon-ami.amazon_linux_2023.id
  }

  # Tags applied to the temporary build instance
  run_tags = {
    Name        = "${var.ami_name_prefix}-build-${var.environment}"
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "packer"
  }
}

# ---------------------------------------------------------------------------
# Build definition
# ---------------------------------------------------------------------------

build {
  name    = "nginx-ami"
  sources = ["source.amazon-ebs.nginx"]

  # Run the Ansible pack playbook to bake nginx into the AMI
  provisioner "ansible" {
    playbook_file = "${path.root}/../ansible/playbooks/pack.yml"
    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_ROLES_PATH=${path.root}/../ansible/roles",
    ]
    extra_arguments = [
      "--extra-vars",
      "environment=${var.environment} project=${var.project}",
    ]
    user = "ec2-user"
  }

  # Manifest file records build output (AMI ID, region, etc.)
  post-processor "manifest" {
    output     = "${path.root}/manifest.json"
    strip_path = true
  }
}
