terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

locals {
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project
      ManagedBy   = "terraform"
    },
    var.tags
  )

  # Map each public/private subnet index to its AZ.
  # Index 0 & 1 → AZ 0, index 2 & 3 → AZ 1.
  public_subnet_az_map  = [for i, _ in var.public_subnet_cidrs : var.availability_zones[floor(i / 2)]]
  private_subnet_az_map = [for i, _ in var.private_subnet_cidrs : var.availability_zones[floor(i / 2)]]
}

# ──────────────────────────────────────────────────────────
# VPC
# ──────────────────────────────────────────────────────────
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-vpc" })
}

# ──────────────────────────────────────────────────────────
# Internet Gateway
# ──────────────────────────────────────────────────────────
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-igw" })
}

# ──────────────────────────────────────────────────────────
# Public Subnets (2 per AZ, 4 total)
# ──────────────────────────────────────────────────────────
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.public_subnet_az_map[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project}-${var.environment}-public-${count.index + 1}"
      Tier = "public"
    }
  )
}

# ──────────────────────────────────────────────────────────
# Private Subnets (2 per AZ, 4 total)
# ──────────────────────────────────────────────────────────
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.private_subnet_az_map[count.index]

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project}-${var.environment}-private-${count.index + 1}"
      Tier = "private"
    }
  )
}

# ──────────────────────────────────────────────────────────
# Elastic IPs & NAT Gateways (one per AZ, in first public subnet of each AZ)
# ──────────────────────────────────────────────────────────
resource "aws_eip" "nat" {
  count  = length(var.availability_zones)
  domain = "vpc"

  tags = merge(
    local.common_tags,
    { Name = "${var.project}-${var.environment}-nat-eip-${count.index + 1}" }
  )

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = length(var.availability_zones)

  # Place each NAT GW in the first public subnet of its respective AZ
  # (index 0 for AZ 0, index 2 for AZ 1)
  subnet_id     = aws_subnet.public[count.index * 2].id
  allocation_id = aws_eip.nat[count.index].id

  tags = merge(
    local.common_tags,
    { Name = "${var.project}-${var.environment}-nat-${count.index + 1}" }
  )

  depends_on = [aws_internet_gateway.this]
}

# ──────────────────────────────────────────────────────────
# Route Tables
# ──────────────────────────────────────────────────────────

# Single shared public route table (all public subnets share the same IGW route)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-rtb-public" })
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One private route table per AZ so each AZ's private subnets use its local NAT GW
resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }

  tags = merge(
    local.common_tags,
    { Name = "${var.project}-${var.environment}-rtb-private-${count.index + 1}" }
  )
}

# Associate private subnets with their AZ's route table
# Private subnet index 0 & 1 → AZ 0 → private route table 0
# Private subnet index 2 & 3 → AZ 1 → private route table 1
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[floor(count.index / 2)].id
}

# ──────────────────────────────────────────────────────────
# Security Group for Interface VPC Endpoints
# ──────────────────────────────────────────────────────────
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project}-${var.environment}-vpce-sg"
  description = "Allow HTTPS traffic from within the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow HTTPS responses to VPC CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-vpce-sg" })
}

# ──────────────────────────────────────────────────────────
# VPC Endpoint – S3 (Gateway type, no extra cost)
# ──────────────────────────────────────────────────────────
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"

  # Associate only with private route tables so private subnets use the endpoint
  # and public subnets do not get direct S3 endpoint routing.
  route_table_ids = aws_route_table.private[*].id

  # Limit S3 endpoint access to common object and bucket operations.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource  = "*"
      }
    ]
  })

  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-vpce-s3" })
}

# ──────────────────────────────────────────────────────────
# VPC Endpoints – SSM (Interface type, requires three services)
# ──────────────────────────────────────────────────────────
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  # Limit SSM endpoint actions to instance management traffic.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssm:ListInstanceAssociations",
          "ssm:DescribeAssociation",
          "ssm:GetDocument",
          "ssm:DescribeDocument",
          "ssm:PutInventory",
          "ssm:PutComplianceItems",
          "ssm:UpdateAssociationStatus"
        ]
        Resource  = "*"
      }
    ]
  })

  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-vpce-ssm" })
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  # Limit SSMMessages endpoint actions to SSM agent channels.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource  = "*"
      }
    ]
  })

  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-vpce-ssmmessages" })
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  # Limit EC2Messages endpoint actions to SSM agent message flow.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource  = "*"
      }
    ]
  })

  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-vpce-ec2messages" })
}
