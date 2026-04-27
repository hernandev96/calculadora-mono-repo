output "vpc_id" {
  description = "ID de la VPC"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "IDs de las subredes públicas"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs de las subredes privadas"
  value       = aws_subnet.private[*].id
}

output "igw_id" {
  description = "ID del Internet Gateway"
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_ids" {
  description = "IDs de los NAT Gateways"
  value       = aws_nat_gateway.this[*].id
}

output "public_route_table_id" {
  description = "ID de la tabla de rutas pública"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "IDs de las tablas de rutas privadas"
  value       = aws_route_table.private[*].id
}

output "security_group_nodes_id" {
  description = "ID del SG para los nodos"
  value       = aws_security_group.nodes.id
}

output "security_group_alb_id" {
  description = "ID del SG para el ALB"
  value       = aws_security_group.alb.id
}

output "security_group_internal_id" {
  description = "ID del SG para la comunicación interna"
  value       = aws_security_group.internal.id
}
