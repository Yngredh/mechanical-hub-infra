output "repository_url" {
  description = "URL do repositorio ECR. Usada como ECR_REGISTRY no pipeline de build."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_name" {
  description = "Nome do repositorio ECR."
  value       = aws_ecr_repository.this.name
}

output "repository_arn" {
  description = "ARN do repositorio ECR."
  value       = aws_ecr_repository.this.arn
}

output "registry_id" {
  description = "ID da conta AWS que hospeda o registro."
  value       = aws_ecr_repository.this.registry_id
}
