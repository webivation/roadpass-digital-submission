# Roadpass Digital Submission

This repository is a clean submission package for the Roadpass infrastructure exercises. It contains three independent deliverables that build on one another:

1. `aws-vpc-exercise`: Foundational AWS networking with Terraform/Terragrunt.
2. `small-ec2-app`: AMI baking + runtime configuration and scalable EC2 application deployment.
3. `deploying-an-application`: Kubernetes Helm deployment assets and a GitHub Actions OIDC-based deployment workflow.

No prior commit history was carried over from the source repository. This repository starts from a fresh submission commit.

## Repository Structure

```text
.
├── .github/
│   └── workflows/
│       └── deploy-staging.yml
├── aws-vpc-exercise/
│   ├── modules/
│   │   └── vpc/
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
│   ├── staging/
│   │   └── terragrunt.hcl
│   ├── terragrunt.hcl
│   └── README.md
├── small-ec2-app/
│   ├── ansible/
│   │   ├── playbooks/
│   │   │   ├── pack.yml
│   │   │   └── fry.yml
│   │   └── roles/
│   │       ├── pack/
│   │       └── fry/
│   ├── modules/
│   │   └── ec2-app/
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
│   ├── packer/
│   │   ├── nginx-ami.pkr.hcl
│   │   └── vars/
│   │       └── staging.pkrvars.hcl
│   ├── staging/
│   │   └── terragrunt.hcl
│   ├── terragrunt.hcl
│   └── README.md
└── deploying-an-application/
    ├── helm/
    │   └── nginx-app/
    │       ├── Chart.yaml
    │       ├── values.yaml
    │       └── templates/
    │           ├── _helpers.tpl
    │           ├── deployment.yaml
    │           ├── service.yaml
    │           ├── ingress.yaml
    │           ├── serviceaccount.yaml
    │           └── hpa.yaml
    └── README.md
```

## Project Overview

### 1) aws-vpc-exercise
Purpose: provision a reusable staging VPC baseline in AWS using Terraform modules managed by Terragrunt.

What it provisions:
- VPC CIDR supernet `172.16.0.0/16`
- Two availability zones
- Four public subnets (two per AZ)
- Four private subnets (two per AZ)
- Internet gateway
- NAT gateways (one per AZ) with EIPs
- Route tables and subnet associations for public/private traffic patterns
- VPC endpoints:
  - S3 Gateway endpoint (private route tables)
  - SSM Interface endpoint
  - SSMMessages Interface endpoint
  - EC2Messages Interface endpoint

Why it exists:
- Establishes secure networking and endpoint access patterns for downstream workloads.
- Produces outputs consumed by other stacks.

### 2) small-ec2-app
Purpose: build and run a highly available nginx-based EC2 application stack using Packer + Ansible + Terraform/Terragrunt.

Core components:
- Packer image pipeline (`packer/nginx-ami.pkr.hcl`)
  - Uses latest Amazon Linux 2023 base image
  - Runs Ansible `pack` playbook during image build
- Ansible pack/fry pattern
  - `pack` role: installs nginx and stages runtime artifacts
  - `fry` role: applies launch-time configuration from EC2 user-data
- Terraform module (`modules/ec2-app`)
  - Launch Template
  - Auto Scaling Group (desired/min of 2 instances)
  - Application Load Balancer + target group + listeners
  - IAM role/profile/policy for instance management
  - Security groups for ALB-to-EC2 traffic and SSH management CIDRs
- Terragrunt staging config wired to VPC outputs from `aws-vpc-exercise/staging`

Why it exists:
- Demonstrates immutable image creation plus runtime customization.
- Delivers a resilient web workload across private subnets behind an ALB.

### 3) deploying-an-application
Purpose: provide Kubernetes packaging and CI/CD automation for deploying nginx to a staging EKS cluster.

Core components:
- Helm chart (`helm/nginx-app`)
  - Deployment, Service, Ingress templates
  - Optional HPA and ServiceAccount templates
  - Value-driven configuration through `values.yaml`
- GitHub Actions workflow (`.github/workflows/deploy-staging.yml`)
  - Uses GitHub OIDC to assume an AWS IAM role (no long-lived AWS keys)
  - Updates kubeconfig for staging EKS cluster
  - Renders Helm templates and performs `helm upgrade --install`

Why it exists:
- Demonstrates modern cloud-native deployment with secure CI identity federation.
- Provides repeatable app release process into Kubernetes.

## Relationship Between Projects

Execution order for a full environment setup:
1. Deploy `aws-vpc-exercise` to create network and endpoint foundation.
2. Build AMI and deploy `small-ec2-app`, consuming VPC outputs.
3. Deploy Kubernetes app via Helm and GitHub Actions in `deploying-an-application`.

Together, these projects showcase infrastructure provisioning, image baking, runtime app deployment, and CI/CD automation on AWS.

## Notes

- This submission repository is intentionally detached from original git history.
- Each subproject includes its own README with implementation-specific usage details and commands.
