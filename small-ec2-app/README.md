# small-ec2-app

A complete infrastructure-as-code solution that deploys a highly-available nginx web server on AWS using **Packer**, **Ansible**, and **Terraform / Terragrunt**.

---

## Architecture

```
Internet
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│                        VPC (user-supplied)                      │
│                                                                 │
│  ┌─────────────── Public Subnets (AZ1 & AZ2) ───────────────┐  │
│  │                                                           │  │
│  │           ┌──────────────────────────────┐               │  │
│  │           │   Application Load Balancer  │               │  │
│  │           │          (ALB)               │               │  │
│  │           │   HTTP :80  (HTTPS :443 opt) │               │  │
│  │           └──────────────┬───────────────┘               │  │
│  └──────────────────────────┼────────────────────────────────┘  │
│                             │                                   │
│  ┌─────────────── Private Subnets (AZ1 & AZ2) ─────────────┐   │
│  │                          │                               │   │
│  │    ┌─────────────────────▼─────────────────────────┐    │   │
│  │    │          Auto Scaling Group (min 2)            │    │   │
│  │    │                                                │    │   │
│  │    │   ┌───────────────┐   ┌───────────────┐       │    │   │
│  │    │   │  EC2 (AZ1)    │   │  EC2 (AZ2)    │       │    │   │
│  │    │   │  nginx :80    │   │  nginx :80    │       │    │   │
│  │    │   │  /health      │   │  /health      │       │    │   │
│  │    │   └───────────────┘   └───────────────┘       │    │   │
│  │    └────────────────────────────────────────────────┘    │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Pack / Fry Idiom

This project uses the **pack / fry** pattern to separate AMI creation from instance configuration:

| Phase | Tool | When | What happens |
|-------|------|------|-------------|
| **Pack** | Packer + Ansible `pack` role | AMI build time | Installs nginx, Ansible, stages the fry playbook & systemd service onto the image |
| **Fry** | Ansible `fry` role (via systemd) | EC2 launch time | Reads JSON from EC2 user-data, renders environment-specific `index.html`, restarts nginx |

The Launch Template's `user_data` field contains a JSON payload consumed by the `fry` role:

```json
{
  "environment":  "staging",
  "project":      "roadpass",
  "site_title":   "Roadpass – Staging",
  "site_heading": "Welcome to Roadpass Staging",
  "site_body":    "This nginx server was baked with Packer, configured with Ansible, and deployed via Terraform."
}
```

---

## Repository Layout

```
small-ec2-app/
├── .gitignore
├── README.md
├── terragrunt.hcl               ← Root Terragrunt config (remote state, provider, common inputs)
│
├── packer/
│   ├── nginx-ami.pkr.hcl        ← Packer HCL2 template
│   └── vars/
│       └── staging.pkrvars.hcl  ← Staging variable overrides
│
├── ansible/
│   ├── ansible.cfg
│   ├── playbooks/
│   │   ├── pack.yml             ← Packer provisioner playbook
│   │   └── fry.yml              ← Launch-time playbook (also staged on AMI)
│   └── roles/
│       ├── pack/                ← AMI bake-time role
│       │   ├── defaults/main.yml
│       │   ├── handlers/main.yml
│       │   ├── tasks/main.yml
│       │   └── templates/
│       │       ├── index.html.j2
│       │       ├── nginx.conf.j2
│       │       └── fry-bootstrap.sh.j2
│       └── fry/                 ← Instance launch-time role
│           ├── defaults/main.yml
│           ├── handlers/main.yml
│           ├── tasks/main.yml
│           └── templates/
│               └── index.html.j2
│
├── modules/
│   └── ec2-app/
│       ├── main.tf              ← Security groups, IAM, Launch Template, ALB, ASG
│       ├── variables.tf
│       └── outputs.tf
│
└── staging/
    └── terragrunt.hcl           ← Staging environment configuration
```

---

## Resources Created

| Resource | Count | Details |
|----------|-------|---------|
| `aws_security_group` (ALB) | 1 | HTTP/HTTPS from 0.0.0.0/0, all outbound |
| `aws_security_group` (EC2) | 1 | HTTP from ALB SG, SSH from management CIDRs |
| `aws_iam_role` | 1 | EC2 instance role |
| `aws_iam_policy` | 1 | Manageable policy (SSM, CloudWatch, S3 read) |
| `aws_iam_instance_profile` | 1 | Attached to Launch Template |
| `aws_launch_template` | 1 | AMI, instance type, user-data, IMDSv2 |
| `aws_lb` (ALB) | 1 | Internet-facing, in public subnets |
| `aws_lb_target_group` | 1 | HTTP, `/health` health-check |
| `aws_lb_listener` (HTTP) | 1 | Forwards to TG (or redirects to HTTPS) |
| `aws_lb_listener` (HTTPS) | 0–1 | Only created when `certificate_arn` is set |
| `aws_autoscaling_group` | 1 | Desired 2, min 2, max 4; in private subnets |

---

## Prerequisites

| Tool | Minimum version |
|------|-----------------|
| [Packer](https://developer.hashicorp.com/packer) | 1.9.0 |
| [Ansible](https://docs.ansible.com/) | 2.14 |
| [Terraform](https://www.terraform.io/) | 1.5.0 |
| [Terragrunt](https://terragrunt.gruntwork.io/) | 0.50.0 |
| AWS credentials | — |

---

## Remote State Setup

Terraform state is stored in S3 with DynamoDB locking. Create the backend resources once per environment:

```bash
# Replace <ACCOUNT_ID> and <ENV> (e.g. staging) as appropriate
aws s3api create-bucket \
  --bucket roadpass-terraform-state-<ENV> \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket roadpass-terraform-state-<ENV> \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket roadpass-terraform-state-<ENV> \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws dynamodb create-table \
  --table-name roadpass-terraform-locks-<ENV> \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

---

## Step 1 – Build the AMI with Packer

```bash
cd packer

# Install required Packer plugins
packer init nginx-ami.pkr.hcl

# Build the AMI for staging
packer build -var-file=vars/staging.pkrvars.hcl nginx-ami.pkr.hcl
```

The resulting AMI ID is written to `packer/manifest.json`. Copy it into
`staging/terragrunt.hcl` as the `ami_id` input.

---

## Step 2 – Configure Staging Inputs

Edit `staging/terragrunt.hcl` and fill in your real AWS resource IDs:

```hcl
vpc_id             = "vpc-0abc123..."
public_subnet_ids  = ["subnet-0pub1...", "subnet-0pub2..."]
private_subnet_ids = ["subnet-0priv1...", "subnet-0priv2..."]
ami_id             = "ami-0xyz..."   # from packer/manifest.json
key_name           = "my-key-pair"   # optional – omit to use SSM Session Manager
certificate_arn    = ""              # optional – set ACM ARN for HTTPS
```

> **Tip:** If you have already deployed the `aws-vpc-exercise` stack you can
> use a Terragrunt `dependency` block to pull VPC outputs automatically.

---

## Step 3 – Deploy with Terragrunt

```bash
cd staging
terragrunt init
terragrunt plan
terragrunt apply
```

After `apply` completes, the ALB DNS name is printed as the `alb_dns_name` output:

```
alb_dns_name = "roadpass-staging-alb-1234567890.us-east-1.elb.amazonaws.com"
```

Open that URL in a browser to see the nginx welcome page.

---

## Outputs Reference

| Output | Description |
|--------|-------------|
| `alb_dns_name` | ALB DNS name – browse here to reach nginx |
| `alb_arn` | ALB ARN |
| `alb_zone_id` | Hosted zone ID (for Route 53 alias records) |
| `alb_security_group_id` | ALB security group ID |
| `target_group_arn` | ALB target group ARN |
| `http_listener_arn` | HTTP listener ARN |
| `https_listener_arn` | HTTPS listener ARN (empty if TLS not configured) |
| `asg_name` | Auto Scaling Group name |
| `asg_arn` | Auto Scaling Group ARN |
| `launch_template_id` | Launch Template ID |
| `launch_template_latest_version` | Latest Launch Template version |
| `resolved_ami_id` | AMI ID in use (Packer-built or latest AL2023) |
| `ec2_iam_role_arn` | EC2 IAM role ARN |
| `ec2_iam_policy_arn` | Manageable IAM policy ARN |
| `ec2_instance_profile_arn` | EC2 instance profile ARN |
| `ec2_security_group_id` | EC2 security group ID |

---

## Optional: Enable HTTPS with ACM

1. Request or import a certificate in [AWS Certificate Manager](https://console.aws.amazon.com/acm).
2. Copy the certificate ARN.
3. Set `certificate_arn` in `staging/terragrunt.hcl`.
4. Re-run `terragrunt apply`.

An HTTPS listener on port 443 will be created and HTTP traffic will be
automatically redirected to HTTPS.

---

## Destroy

```bash
cd staging
terragrunt destroy
```
