output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.this.id
}

output "public_subnet_ids" {
  description = "IDs of all public subnets (4 total, 2 per AZ)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of all private subnets (4 total, 2 per AZ)"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids_az1" {
  description = "IDs of the two public subnets in the first availability zone"
  value       = [aws_subnet.public[0].id, aws_subnet.public[1].id]
}

output "public_subnet_ids_az2" {
  description = "IDs of the two public subnets in the second availability zone"
  value       = [aws_subnet.public[2].id, aws_subnet.public[3].id]
}

output "private_subnet_ids_az1" {
  description = "IDs of the two private subnets in the first availability zone"
  value       = [aws_subnet.private[0].id, aws_subnet.private[1].id]
}

output "private_subnet_ids_az2" {
  description = "IDs of the two private subnets in the second availability zone"
  value       = [aws_subnet.private[2].id, aws_subnet.private[3].id]
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways (one per AZ)"
  value       = aws_nat_gateway.this[*].id
}

output "nat_gateway_public_ips" {
  description = "Public (Elastic) IPs of the NAT Gateways"
  value       = aws_eip.nat[*].public_ip
}

output "public_route_table_id" {
  description = "ID of the shared public route table"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "IDs of the per-AZ private route tables"
  value       = aws_route_table.private[*].id
}

output "s3_vpc_endpoint_id" {
  description = "ID of the S3 Gateway VPC endpoint"
  value       = aws_vpc_endpoint.s3.id
}

output "ssm_vpc_endpoint_id" {
  description = "ID of the SSM Interface VPC endpoint"
  value       = aws_vpc_endpoint.ssm.id
}

output "ssmmessages_vpc_endpoint_id" {
  description = "ID of the SSM Messages Interface VPC endpoint"
  value       = aws_vpc_endpoint.ssmmessages.id
}

output "ec2messages_vpc_endpoint_id" {
  description = "ID of the EC2 Messages Interface VPC endpoint"
  value       = aws_vpc_endpoint.ec2messages.id
}

output "vpc_endpoints_security_group_id" {
  description = "ID of the security group attached to Interface VPC endpoints"
  value       = aws_security_group.vpc_endpoints.id
}
