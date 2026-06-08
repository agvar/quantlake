output "vpc_id" {
  description = "The VPC ID -- consumed by Glue connections, RDS subnet groups, Redshift workgroups."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR. Useful for downstream SG rules that allow intra-VPC traffic."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs (one per AZ)."
  value       = [for s in aws_subnet.public : s.id]
}

output "private_app_subnet_ids" {
  description = "Private app-tier subnet IDs. Use for Lambda-in-VPC, Glue connection, ECS tasks."
  value       = [for s in aws_subnet.private_app : s.id]
}

output "private_data_subnet_ids" {
  description = "Private data-tier subnet IDs. Use for RDS subnet group, ElastiCache, Redshift."
  value       = [for s in aws_subnet.private_data : s.id]
}

output "s3_endpoint_id"        { value = aws_vpc_endpoint.s3.id }
output "dynamodb_endpoint_id"  { value = aws_vpc_endpoint.dynamodb.id }
output "vpce_security_group_id" {
  description = "SG attached to interface endpoints; null if no interface endpoints enabled."
  value       = length(aws_security_group.vpce) > 0 ? aws_security_group.vpce[0].id : null
}
