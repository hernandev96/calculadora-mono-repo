output "vpc_id" {
  description = "VPC id"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Public subnet ids"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet ids"
  value       = aws_subnet.private[*].id
}

output "igw_id" {
  description = "Internet Gateway id"
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_ids" {
  description = "NAT Gateway ids"
  value       = aws_nat_gateway.this[*].id
}

output "public_route_table_id" {
  description = "Public route table id"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "Private route table ids"
  value       = aws_route_table.private[*].id
}

output "security_group_nodes_id" {
  description = "SG id for nodes"
  value       = aws_security_group.nodes.id
}

output "security_group_alb_id" {
  description = "SG id for ALB"
  value       = aws_security_group.alb.id
}

output "security_group_internal_id" {
  description = "SG id for internal communication"
  value       = aws_security_group.internal.id
}
