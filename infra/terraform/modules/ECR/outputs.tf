output "repository_name" {
  description = "Nombre del repositorio ECR"
  value       = aws_ecr_repository.ecr.name
}

output "repository_url" {
  description = "URL del repositorio ECR"
  value       = aws_ecr_repository.ecr.repository_url
}

output "registry_id" {
  description = "ID del registro ECR"
  value       = aws_ecr_repository.ecr.registry_id
}

output "repository_arn" {
  description = "ARN del repositorio ECR"
  value       = aws_ecr_repository.ecr.arn
}
