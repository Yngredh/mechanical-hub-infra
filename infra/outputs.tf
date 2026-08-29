# =============================================================================
# Contrato entre repositorios (ADR-0004)
#
# Estes outputs sao interface publica: alterar ou remover qualquer um deles e
# uma mudanca quebra-compatibilidade e exige coordenacao com os consumidores.
#
# Consumidores:
#   - mechanical-hub-database : vpc_id, private_subnet_ids, private_subnet_cidrs,
#                               vpc_cidr (fallback), eks_cluster_security_group_id
#   - mechanical-hub-auth     : vpc_id, private_subnet_ids, app_nlb_arn,
#                               app_backend_base_url
#   - mechanical-hub (CI)     : eks_cluster_name, eks_cluster_endpoint,
#                               ecr_repository_url
# =============================================================================

# ── Rede ─────────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "ID da VPC da plataforma."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "Bloco CIDR da VPC. Fallback de liberacao quando os CIDRs de subnet nao bastam."
  value       = module.vpc.vpc_cidr
}

output "private_subnet_ids" {
  description = "Subnets privadas. Usadas pelos nodes do EKS e pelo DB subnet group do RDS."
  value       = module.vpc.private_subnet_ids
}

output "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas. Usados nas regras de entrada do banco."
  value       = module.vpc.private_subnet_cidrs
}

output "public_subnet_ids" {
  description = "Subnets publicas. Usadas pelos load balancers expostos pelo cluster."
  value       = module.vpc.public_subnet_ids
}

output "public_subnet_cidrs" {
  description = "CIDRs das subnets publicas."
  value       = module.vpc.public_subnet_cidrs
}

output "availability_zones" {
  description = "AZs efetivamente usadas pelas subnets privadas."
  value       = module.vpc.availability_zones
}

# ── EKS ──────────────────────────────────────────────────────────────────────

output "eks_cluster_name" {
  description = "Nome do cluster EKS. Usado em: aws eks update-kubeconfig --name <valor>"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint do API server do cluster EKS."
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_security_group_id" {
  description = <<-EOT
    Security group gerenciado pelo EKS e anexado a todos os nodes.

    E este o SG que os consumidores devem liberar quando quiserem autorizar o
    trafego vindo do cluster (ex.: allowed_security_group_ids no repositorio
    mechanical-hub-database).
  EOT
  value       = module.eks.cluster_security_group_id
}

output "eks_node_security_group_id" {
  description = "Security group adicional dos nodes, criado por este repositorio."
  value       = module.eks.node_security_group_id
}

output "eks_cluster_ca_certificate" {
  description = "Certificado da CA do cluster, em base64. Usado para montar o kubeconfig."
  value       = module.eks.cluster_ca_certificate
}

# ── ECR ──────────────────────────────────────────────────────────────────────

output "ecr_repository_url" {
  description = "URL do repositorio ECR. Usada como ECR_REGISTRY no pipeline de build."
  value       = module.ecr.repository_url
}

output "ecr_repository_name" {
  description = "Nome do repositorio ECR."
  value       = module.ecr.repository_name
}

output "ecr_registry_id" {
  description = "ID da conta AWS que hospeda o registro ECR."
  value       = module.ecr.registry_id
}

# ── NLB interno da aplicacao ──────────────────────────────────────────────────

output "app_nlb_arn" {
  description = "ARN do NLB interno da aplicacao. Alvo do aws_api_gateway_vpc_link no mechanical-hub-auth."
  value       = module.app_lb.nlb_arn
}

output "app_backend_base_url" {
  description = <<-EOT
    URL base ja composta (DNS do NLB + porta do NodePort) para as integracoes
    HTTP_PROXY via VPC Link do mechanical-hub-auth. Mesmo espirito do
    ecr_repository_url: o consumidor le um valor pronto, sem montar
    host:porta na mao a partir de outputs separados.
  EOT
  value       = "http://${module.app_lb.nlb_dns_name}:${var.app_node_port}"
}

# ── Observabilidade (RFC-0004) ───────────────────────────────────────────────
#
# Contrato com quem exporta telemetria. O consumidor imediato e o
# mechanical-hub (OTEL_EXPORTER_OTLP_ENDPOINT no Deployment); as Lambdas do
# mechanical-hub-auth entram depois, quando houver um listener no NLB
# apontando para o NodePort do coletor.
#
# Todos ficam nulos com var.observability_enabled = false — o consumidor
# precisa tratar esse caso em vez de assumir que sempre existe um coletor.

output "otlp_grpc_endpoint" {
  description = "Endpoint OTLP/gRPC do coletor OpenTelemetry, para cargas dentro do cluster. Nulo se a observabilidade esta desligada."
  value       = try(module.observability[0].otlp_grpc_endpoint, null)
}

output "otlp_http_endpoint" {
  description = "Endpoint OTLP/HTTP do coletor OpenTelemetry, para cargas dentro do cluster. Nulo se a observabilidade esta desligada."
  value       = try(module.observability[0].otlp_http_endpoint, null)
}

output "observability_namespace" {
  description = "Namespace onde a stack de observabilidade foi instalada. Nulo se desligada."
  value       = try(module.observability[0].namespace, null)
}

output "otlp_vpc_endpoint" {
  description = <<-EOT
    Endereco OTLP/HTTP alcancavel de dentro da VPC, porem FORA do cluster — via
    listener no NLB interno. E o valor de OTEL_EXPORTER_OTLP_ENDPOINT das
    Lambdas do mechanical-hub-auth, que nao resolvem o DNS do Kubernetes.

    Nulo quando a observabilidade esta desligada ou quando
    observability_otlp_http_node_port e nulo.
  EOT
  value       = module.app_lb.otlp_backend_url
}

output "grafana_port_forward_command" {
  description = <<-EOT
    Comando pronto para abrir o Grafana em http://localhost:3000 (usuario
    admin, senha em TF_VAR_grafana_admin_password).

    Nao ha Ingress de proposito: expor uma interface administrativa na
    internet, a partir de um cluster de laboratorio com credenciais rotativas,
    nao se justifica.
  EOT
  value       = try(module.observability[0].grafana_port_forward_command, null)
}
