output "repository_urls" {
  description = "URL de cada repositorio ECR, por servico. Usada como ECR_REGISTRY no pipeline de build de cada servico."
  value       = { for s, r in aws_ecr_repository.this : s => r.repository_url }
}

output "repository_names" {
  description = "Nome de cada repositorio ECR, por servico."
  value       = { for s, r in aws_ecr_repository.this : s => r.name }
}

output "repository_arns" {
  description = "ARN de cada repositorio ECR, por servico."
  value       = { for s, r in aws_ecr_repository.this : s => r.arn }
}

output "registry_id" {
  description = "ID da conta AWS que hospeda o registro (o mesmo para todos os repositorios)."
  value       = one(distinct([for r in aws_ecr_repository.this : r.registry_id]))
}
