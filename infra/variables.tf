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
  description = <<-EOT
    Tipo de instancia EC2 dos nodes do EKS.

    t3.large (2 vCPU, 8 GiB) desde a Fase 4: os 4 servicos, o MongoDB e a
    stack de observabilidade nao cabem em t3.medium (4 GiB). O AWS Academy Lab
    limita a conta a 9 instancias e 32 vCPU — ver a validacao de
    eks_node_max_size.
  EOT
  type        = string
  default     = "t3.large"

  validation {
    condition     = contains(["t3.medium", "t3.large"], var.eks_node_instance_type)
    error_message = "Use t3.medium ou t3.large: tipos maiores estouram o limite de vCPU do AWS Academy Lab."
  }
}

variable "eks_node_desired_size" {
  description = <<-EOT
    Quantidade desejada de nodes.

    Passou de 2 para 3 quando a stack de observabilidade entrou (RFC-0004) e
    continua 3 na Fase 4, agora em t3.large: 6 vCPU e 24 GiB para os 4
    servicos, o MongoDB e a observabilidade.
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
  description = <<-EOT
    Quantidade maxima de nodes. O AWS Academy Lab aceita no maximo 9
    instancias e 32 vCPU na conta; 5 x t3.large (10 vCPU) deixa folga para o
    que roda fora do cluster.
  EOT
  type        = number
  default     = 5

  validation {
    condition     = var.eks_node_max_size <= 9 && var.eks_node_max_size * 2 <= 32
    error_message = "eks_node_max_size passa do limite do AWS Academy Lab (9 instancias, 32 vCPU)."
  }
}

variable "eks_node_metadata_hop_limit" {
  description = <<-EOT
    Hop limit do IMDSv2 nos nodes. Precisa ser >= 2: os pods leem as
    credenciais da LabRole pelo IMDS para falar com SQS e EBS.
  EOT
  type        = number
  default     = 2
}

variable "eks_ebs_csi_enabled" {
  description = <<-EOT
    Instala o addon aws-ebs-csi-driver (sem IRSA, usando a LabRole dos nodes)
    e a StorageClass gp3 (WaitForFirstConsumer). E o que da volume ao MongoDB
    do mechanical-hub-database e, opcionalmente, a observabilidade.

    Se o driver falhar por permissao no Lab, desligue: o MongoDB passa a usar
    armazenamento efemero e storage_class_name vira nulo.
  EOT
  type        = bool
  default     = true
}

# ── Servicos da aplicacao (Fase 4, ADR-0005) ─────────────────────────────────

variable "services" {
  description = <<-EOT
    Servicos da aplicacao e o contrato de porta de cada um.

    Cada chave gera um repositorio ECR (<project>/<servico>) e, no NLB interno,
    um target group + listener na node_port informada. A node_port e a
    NodePort fixa do Service do servico — mudar aqui exige mudar o manifesto
    no repositorio do servico junto.
  EOT
  type = map(object({
    node_port         = number
    health_check_path = optional(string, "/actuator/health/readiness")
  }))
  default = {
    orders       = { node_port = 30080 }
    stock        = { node_port = 30081 }
    billing      = { node_port = 30082 }
    orchestrator = { node_port = 30083 }
  }

  validation {
    condition     = alltrue([for s in values(var.services) : s.node_port >= 30000 && s.node_port <= 32767])
    error_message = "Toda node_port precisa estar na faixa 30000-32767."
  }

  validation {
    condition     = length(distinct([for s in values(var.services) : s.node_port])) == length(var.services)
    error_message = "Cada servico precisa de uma node_port propria."
  }
}

# ── SQS (ADR-0006) ───────────────────────────────────────────────────────────

variable "sqs_queues" {
  description = <<-EOT
    Filas FIFO da saga, cada uma com DLQ propria. As chaves sao contrato com
    os servicos: aparecem como chaves dos outputs sqs_queue_urls,
    sqs_queue_arns e sqs_dlq_urls.
  EOT
  type        = list(string)
  default     = ["orders-commands", "stock-commands", "billing-commands", "orchestrator-events"]
}

# ── ECR ──────────────────────────────────────────────────────────────────────

variable "ecr_image_retention_count" {
  description = "Quantidade de imagens com tag mantidas no ECR antes da limpeza."
  type        = number
  default     = 10
}

# ── Aplicacao ────────────────────────────────────────────────────────────────
#
# O contrato de porta de cada servico com o NLB interno esta em var.services.

variable "app_namespace" {
  description = <<-EOT
    Namespace onde os servicos da aplicacao rodam. As regras de alerta e os
    paineis olham para os pods deste namespace.
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

    Ligar exige o driver EBS CSI — ver var.eks_ebs_csi_enabled. Os volumes
    usam a StorageClass gp3 criada pelo modulo eks.
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
