# outputs.tf
# ---------------------------------------------------------------------------
# Useful values surfaced after `terraform apply`. The most important is
# alb_dns_name - open it in a browser to see the working demo and verify the
# full traffic path.
# ---------------------------------------------------------------------------

output "aws_region" {
  description = "Region the infrastructure was deployed into."
  value       = var.aws_region
}

output "account_id" {
  description = "AWS account ID the resources belong to."
  value       = data.aws_caller_identity.current.account_id
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public (web/LB tier) subnets."
  value       = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  description = "IDs of the private application-tier subnets."
  value       = aws_subnet.app[*].id
}

output "db_subnet_ids" {
  description = "IDs of the isolated database-tier subnets."
  value       = aws_subnet.db[*].id
}

output "alb_dns_name" {
  description = "Public DNS name of the load balancer. Open this in a browser to test the demo."
  value       = aws_lb.web.dns_name
}

output "alb_url" {
  description = "Convenience HTTP URL for the demo."
  value       = "http://${aws_lb.web.dns_name}"
}

output "app_security_group_id" {
  description = "Security group ID of the application tier."
  value       = aws_security_group.app.id
}

output "db_security_group_id" {
  description = "Security group ID of the database tier."
  value       = aws_security_group.db.id
}

output "db_endpoint" {
  description = "RDS endpoint (host:port). Private - only reachable from the app tier."
  value       = aws_db_instance.main.endpoint
}

output "db_password_ssm_parameter" {
  description = "Name of the SSM SecureString parameter holding the DB password. The value itself is never output."
  value       = aws_ssm_parameter.db_password.name
}
