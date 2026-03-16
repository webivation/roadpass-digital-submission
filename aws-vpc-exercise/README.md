# AWS VPC Exercise

Terraform module for creating a staging VPC in AWS, managed with Terragrunt.

## Architecture

```
172.16.0.0/16
│
├── Internet Gateway
│
├── AZ: us-east-1a
│   ├── Public Subnet 1  – 172.16.1.0/24  ─┐
│   ├── Public Subnet 2  – 172.16.2.0/24  ─┤─► Public Route Table (→ IGW)
│   │                                       │
│   ├── NAT Gateway (EIP) in Public Subnet 1
│   │
│   ├── Private Subnet 1 – 172.16.11.0/24 ─┐
│   └── Private Subnet 2 – 172.16.12.0/24 ─┴─► Private Route Table AZ1 (→ NAT GW 1)
│
└── AZ: us-east-1b
    ├── Public Subnet 3  – 172.16.3.0/24  ─┐
    ├── Public Subnet 4  – 172.16.4.0/24  ─┴─► Public Route Table (→ IGW)
    │
    ├── NAT Gateway (EIP) in Public Subnet 3
    │
    ├── Private Subnet 3 – 172.16.13.0/24 ─┐
    └── Private Subnet 4 – 172.16.14.0/24 ─┴─► Private Route Table AZ2 (→ NAT GW 2)

VPC Endpoints (internal, no traffic leaves the AWS network):
  • S3       – Gateway endpoint, associated with all route tables
  • SSM      – Interface endpoint (private DNS), in all private subnets
  • SSMMessages – Interface endpoint (private DNS), in all private subnets
  • EC2Messages – Interface endpoint (private DNS), in all private subnets
```

### Resources Created

| Resource | Count | Details |
|---|---|---|
| VPC | 1 | 172.16.0.0/16, DNS support & hostnames enabled |
| Internet Gateway | 1 | Attached to the VPC |
| Public Subnets | 4 | 2 per AZ, auto-assign public IP |
| Private Subnets | 4 | 2 per AZ |
| Elastic IPs | 2 | One per NAT Gateway |
| NAT Gateways | 2 | One per AZ, placed in first public subnet of each AZ |
| Route Tables | 3 | 1 public (shared) + 1 private per AZ |
| Route Table Associations | 8 | 4 public + 4 private |
| S3 VPC Endpoint | 1 | Gateway type, no additional cost |
| SSM VPC Endpoint | 1 | Interface type, private DNS |
| SSMMessages VPC Endpoint | 1 | Interface type, private DNS |
| EC2Messages VPC Endpoint | 1 | Interface type, private DNS |
| Security Group (endpoints) | 1 | HTTPS ingress from VPC CIDR |

## Repository Layout

```
aws-vpc-exercise/
├── README.md                   ← this file
├── terragrunt.hcl              ← root config: remote state, provider, common inputs
├── modules/
│   └── vpc/
│       ├── main.tf             ← all resources
│       ├── variables.tf        ← input variables
│       └── outputs.tf          ← outputs
└── staging/
    └── terragrunt.hcl          ← staging environment instantiation
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5.0
- [Terragrunt](https://terragrunt.gruntwork.io/docs/getting-started/install/) >= 0.50.0
- AWS credentials configured (environment variables, `~/.aws/credentials`, or IAM role)
- An S3 bucket and DynamoDB table for Terraform remote state (see **Remote State** below)

## Remote State

The root `terragrunt.hcl` is configured to store state in S3 with DynamoDB locking.
Create these resources once before the first `apply` (make sure the S3 bucket name is globally unique and matches the backend configuration in `terragrunt.hcl`):

```bash
# Configuration
# Choose a globally unique bucket name and ensure it matches the S3 backend bucket in terragrunt.hcl.
# Example pattern: my-terraform-state-<your-account-id>-staging
BUCKET_NAME="my-terraform-state-<your-account-id>-staging"
REGION="us-east-1"
LOCK_TABLE_NAME="roadpass-terraform-locks-staging"

# S3 bucket
aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$REGION"

aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# DynamoDB table for state locking
aws dynamodb create-table \
  --table-name "$LOCK_TABLE_NAME" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"
```

## Deploy the Staging VPC

```bash
cd aws-vpc-exercise/staging

# Preview changes
terragrunt plan

# Apply changes
terragrunt apply
```

Terragrunt will automatically:
1. Generate `provider.tf` (AWS provider with default tags)
2. Generate `backend.tf` (S3 remote state)
3. Source the `../modules/vpc` Terraform module

## Using the Module Directly (without Terragrunt)

```hcl
module "vpc" {
  source = "./modules/vpc"

  project     = "roadpass"
  environment = "staging"
  region      = "us-east-1"
  vpc_cidr    = "172.16.0.0/16"

  availability_zones = ["us-east-1a", "us-east-1b"]

  public_subnet_cidrs = [
    "172.16.1.0/24",
    "172.16.2.0/24",
    "172.16.3.0/24",
    "172.16.4.0/24",
  ]

  private_subnet_cidrs = [
    "172.16.11.0/24",
    "172.16.12.0/24",
    "172.16.13.0/24",
    "172.16.14.0/24",
  ]
}
```

## Outputs

| Output | Description |
|---|---|
| `vpc_id` | VPC ID |
| `vpc_cidr_block` | VPC CIDR block |
| `internet_gateway_id` | Internet Gateway ID |
| `public_subnet_ids` | All 4 public subnet IDs |
| `private_subnet_ids` | All 4 private subnet IDs |
| `public_subnet_ids_az1` | Public subnet IDs in AZ 1 |
| `public_subnet_ids_az2` | Public subnet IDs in AZ 2 |
| `private_subnet_ids_az1` | Private subnet IDs in AZ 1 |
| `private_subnet_ids_az2` | Private subnet IDs in AZ 2 |
| `nat_gateway_ids` | NAT Gateway IDs (one per AZ) |
| `nat_gateway_public_ips` | Elastic IPs of NAT Gateways |
| `public_route_table_id` | Shared public route table ID |
| `private_route_table_ids` | Per-AZ private route table IDs |
| `s3_vpc_endpoint_id` | S3 Gateway endpoint ID |
| `ssm_vpc_endpoint_id` | SSM Interface endpoint ID |
| `ssmmessages_vpc_endpoint_id` | SSMMessages Interface endpoint ID |
| `ec2messages_vpc_endpoint_id` | EC2Messages Interface endpoint ID |
| `vpc_endpoints_security_group_id` | Security group ID for Interface endpoints |

## Destroy

```bash
cd aws-vpc-exercise/staging
terragrunt destroy
```