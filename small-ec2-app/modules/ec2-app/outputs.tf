# ---------------------------------------------------------------------------
# Load Balancer
# ---------------------------------------------------------------------------

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer – use this to reach the nginx site"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the ALB (for Route 53 alias records)"
  value       = aws_lb.this.zone_id
}

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "target_group_arn" {
  description = "ARN of the ALB target group"
  value       = aws_lb_target_group.this.arn
}

output "http_listener_arn" {
  description = "ARN of the HTTP (port 80) ALB listener"
  value       = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS (port 443) ALB listener (empty when TLS is not configured)"
  value       = length(aws_lb_listener.https) > 0 ? aws_lb_listener.https[0].arn : ""
}

# ---------------------------------------------------------------------------
# Auto Scaling Group
# ---------------------------------------------------------------------------

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.this.name
}

output "asg_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.this.arn
}

# ---------------------------------------------------------------------------
# Launch Template
# ---------------------------------------------------------------------------

output "launch_template_id" {
  description = "ID of the EC2 launch template"
  value       = aws_launch_template.this.id
}

output "launch_template_latest_version" {
  description = "Latest version number of the EC2 launch template"
  value       = aws_launch_template.this.latest_version
}

output "resolved_ami_id" {
  description = "AMI ID used by the launch template (either var.ami_id or the latest Amazon Linux 2023)"
  value       = local.resolved_ami_id
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------

output "ec2_iam_role_arn" {
  description = "ARN of the IAM role attached to the EC2 instances"
  value       = aws_iam_role.ec2.arn
}

output "ec2_iam_policy_arn" {
  description = "ARN of the manageable IAM policy attached to the EC2 role"
  value       = aws_iam_policy.ec2.arn
}

output "ec2_instance_profile_arn" {
  description = "ARN of the EC2 instance profile"
  value       = aws_iam_instance_profile.ec2.arn
}

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------

output "ec2_security_group_id" {
  description = "ID of the EC2 instances security group"
  value       = aws_security_group.ec2.id
}
