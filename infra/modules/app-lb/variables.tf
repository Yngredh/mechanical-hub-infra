variable "project" {
  description = "Nome do projeto, usado como prefixo dos recursos."
  type        = string
}

variable "environment" {
  description = "Ambiente de implantacao (production, staging)."
  type        = string
}

variable "vpc_id" {
  description = "VPC onde o NLB e o target group sao criados."
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets privadas onde o NLB e provisionado (internal = true)."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas. Origem do trafego liberado no node (preserve_client_ip desligado)."
  type        = list(string)
}

variable "node_security_group_id" {
  description = "Security group dos nodes do EKS, onde a regra de ingress do NodePort e criada."
  type        = string
}

variable "autoscaling_group_name" {
  description = "ASG que sustenta o node group do EKS. O target group e anexado a ela."
  type        = string
}

variable "node_port" {
  description = "NodePort fixo do Service da aplicacao. Contrato com o repositorio mechanical-hub."
  type        = number
}

variable "health_check_path" {
  description = "Path HTTP verificado pelo health check do target group, na porta node_port."
  type        = string
}

variable "tags" {
  description = "Tags comuns aplicadas a todos os recursos do modulo."
  type        = map(string)
}

variable "otlp_node_port" {
  description = <<-EOT
    NodePort do endpoint OTLP/HTTP do coletor OpenTelemetry. Nulo nao cria
    listener nenhum e o modulo se comporta como antes.

    Existe para que as Lambdas do mechanical-hub-auth — que rodam na VPC, mas
    fora do Kubernetes — consigam exportar telemetria. Precisa bater com
    var.observability_otlp_http_node_port do modulo de observabilidade.
  EOT
  type        = number
  default     = null
}
