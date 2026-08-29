variable "aws_region" {
  description = "Regiao AWS. O AWS Academy so libera us-east-1 e us-west-2."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-west-2"], var.aws_region)
    error_message = "AWS Academy only allows us-east-1 or us-west-2."
  }
}

variable "project" {
  description = "Nome do projeto, usado como prefixo dos recursos."
  type        = string
  default     = "mechanical-hub"
}

variable "environment" {
  description = "Ambiente de implantacao (production, staging)."
  type        = string
  default     = "production"
}

variable "lab_role_name" {
  description = "Role pre-existente usada pelo cluster e pelos nodes (AWS Academy)."
  type        = string
  default     = "LabRole"
}

# ── VPC ──────────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs de implantacao. Precisam pertencer a var.aws_region."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets publicas (uma por AZ). Usadas pelo load balancer."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = <<-EOT
    CIDRs das subnets privadas (uma por AZ). Usadas pelos nodes do EKS e,
    via output do contrato, pelo RDS provisionado em mechanical-hub-database.
  EOT
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

# ── EKS ──────────────────────────────────────────────────────────────────────

variable "eks_cluster_version" {
  description = "Versao do Kubernetes do cluster EKS."
  type        = string
  default     = "1.33"
}

variable "eks_node_instance_type" {
  description = "Tipo de instancia EC2 dos nodes do EKS."
  type        = string
  default     = "t3.medium"
}

variable "eks_node_desired_size" {
  description = <<-EOT
    Quantidade desejada de nodes.

    Passou de 2 para 3 quando a stack de observabilidade entrou (RFC-0004):
    Prometheus, Loki, Tempo, Grafana e o coletor somam cerca de 0,6 vCPU e
    1,8 GiB apenas em requests, e passariam a disputar espaco com a aplicacao
    e com o HPA em dois t3.medium. Voltar para 2 e uma linha — mas espere pods
    em Pending quando a aplicacao escalar.
  EOT
  type        = number
  default     = 3
}

variable "eks_node_min_size" {
  description = "Quantidade minima de nodes."
  type        = number
  default     = 1
}

variable "eks_node_max_size" {
  description = "Quantidade maxima de nodes."
  type        = number
  default     = 5
}

# ── ECR ──────────────────────────────────────────────────────────────────────

variable "ecr_image_retention_count" {
  description = "Quantidade de imagens com tag mantidas no ECR antes da limpeza."
  type        = number
  default     = 10
}

# ── NLB interno da aplicacao ─────────────────────────────────────────────────
#
# Contrato de porta com o repositorio mechanical-hub: o Service da aplicacao
# expoe type: NodePort nesta porta fixa. Mudar aqui exige mudar la junto.

variable "app_node_port" {
  description = "NodePort fixo do Service da aplicacao (mechanical-hub). Contrato entre os dois repositorios."
  type        = number
  default     = 30080
}

variable "app_health_check_path" {
  description = "Path HTTP verificado pelo health check do target group do NLB, na porta app_node_port."
  type        = string
  default     = "/actuator/health/readiness"
}

variable "app_namespace" {
  description = <<-EOT
    Namespace onde a aplicacao principal (mechanical-hub) roda. As regras de
    alerta e os paineis de infraestrutura olham para os pods deste namespace.
  EOT
  type        = string
  default     = "production"
}

# ── Observabilidade (RFC-0004) ───────────────────────────────────────────────

variable "observability_enabled" {
  description = <<-EOT
    Instala a stack de observabilidade (OpenTelemetry, Prometheus, Loki, Tempo
    e Grafana) no cluster.

    Desligar nao apaga configuracao: o codigo continua versionado e um apply
    posterior devolve tudo. Serve para os momentos em que o cluster do
    laboratorio esta sem folga e a prioridade e a aplicacao no ar.
  EOT
  type        = bool
  default     = true
}

variable "observability_namespace" {
  description = "Namespace da stack de observabilidade."
  type        = string
  default     = "monitoring"
}

variable "grafana_admin_password" {
  description = <<-EOT
    Senha do usuario admin do Grafana.

    Sem default de proposito — uma senha em codigo seria identica em qualquer
    clone do repositorio. Informe via TF_VAR_grafana_admin_password (secret do
    pipeline), como ja e feito com database_password no mechanical-hub-auth.

    So e exigida quando var.observability_enabled = true.
  EOT
  type        = string
  sensitive   = true
  default     = ""
}

variable "observability_metrics_retention" {
  description = <<-EOT
    Retencao das metricas no Prometheus. Precisa cobrir mais de um dia: o
    painel de volume diario de ordens de servico exigido pela Fase 3 so mostra
    tendencia com varios dias de historico.
  EOT
  type        = string
  default     = "7d"
}

variable "observability_logs_retention" {
  description = "Retencao dos logs no Loki (formato de duracao, ex: 168h)."
  type        = string
  default     = "168h"
}

variable "observability_traces_retention" {
  description = "Retencao dos traces no Tempo (formato de duracao, ex: 48h)."
  type        = string
  default     = "48h"
}

variable "observability_persistence_enabled" {
  description = <<-EOT
    Liga volumes persistentes para Prometheus, Loki e Tempo.

    Falso por padrao: e a configuracao que sobe sem nenhuma dependencia extra
    no laboratorio. Com armazenamento efemero, reiniciar um pod zera o
    historico daquele sinal — aceitavel aqui, ja que a RFC-0004 assume que o
    historico nao sobrevive a um reset do ambiente; o que sobrevive e a
    configuracao, que e codigo.

    Ligar exige uma StorageClass funcional — ver
    var.observability_manage_ebs_csi_addon.
  EOT
  type        = bool
  default     = false
}

variable "observability_manage_ebs_csi_addon" {
  description = <<-EOT
    Instala o addon aws-ebs-csi-driver, necessario para PersistentVolumeClaims
    a partir do Kubernetes 1.27 (o provisionador EBS in-tree deixou de
    existir). Criado sem IRSA: o driver usa o instance profile dos nodes.

    So faz sentido junto com var.observability_persistence_enabled = true.
  EOT
  type        = bool
  default     = false
}

variable "observability_otlp_http_node_port" {
  description = <<-EOT
    NodePort do endpoint OTLP/HTTP do coletor, e porta do listener criado no
    NLB interno para alcanca-lo.

    Existe porque as Lambdas do mechanical-hub-auth rodam na VPC mas fora do
    Kubernetes: elas nao resolvem o DNS interno do cluster e nao chegam ao
    Service ClusterIP do coletor. O caminho e o mesmo ja usado pela aplicacao
    na porta 30080 — NodePort no cluster, listener no NLB.

    Nulo desliga os dois lados de uma vez (Service volta a ClusterIP, nenhum
    listener e criado) e as Lambdas deixam de exportar telemetria.
  EOT
  type        = number
  default     = 30318

  validation {
    condition     = var.observability_otlp_http_node_port == null || try(var.observability_otlp_http_node_port >= 30000 && var.observability_otlp_http_node_port <= 32767, false)
    error_message = "NodePort precisa estar na faixa 30000-32767."
  }
}
