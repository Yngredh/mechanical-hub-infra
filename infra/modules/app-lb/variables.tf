variable "project" {
  description = "Nome do projeto, usado como prefixo dos recursos."
  type        = string
}

variable "environment" {
  description = "Ambiente de implantacao (production, staging)."
  type        = string
}

variable "vpc_id" {
  description = "VPC onde o NLB e os target groups sao criados."
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

variable "cluster_security_group_id" {
  description = <<-EOT
    Cluster security group gerenciado pelo EKS — o que fica anexado aos nodes.
    E nele que as regras de entrada das NodePorts sao criadas.
  EOT
  type        = string
}

variable "autoscaling_group_name" {
  description = "ASG que sustenta o node group do EKS. Os target groups sao anexados a ela."
  type        = string
}

variable "services" {
  description = <<-EOT
    Servico -> { node_port, health_check_path }. Cada item gera um target
    group, um listener na mesma porta e uma regra de entrada no cluster SG.
    A node_port e contrato com o manifesto do Service no repositorio do
    servico.
  EOT
  type = map(object({
    node_port         = number
    health_check_path = string
  }))

  validation {
    condition     = length(var.services) > 0
    error_message = "Informe ao menos um servico."
  }
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
