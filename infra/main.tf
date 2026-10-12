# =============================================================================
# Infraestrutura base da plataforma Mechanical Hub
#
# Escopo deste repositorio (ADR-0004): rede (VPC), cluster de execucao (EKS),
# registro de imagens (ECR) e, desde a Fase 4, as filas SQS da saga. Os bancos
# vivem em `mechanical-hub-database`, que le vpc_id / private_subnet_ids /
# private_subnet_cidrs / storage_class_name do state daqui.
# =============================================================================

locals {
  common_tags = {
    Project     = var.project
    Component   = "infra"
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # Fila que cada servico consome (infrastructure.md §3): o orchestrator le
  # os eventos, os demais leem os proprios comandos. Alimenta o painel de cada
  # servico; servico sem fila correspondente fica com o painel de fila vazio.
  service_consumed_queue = {
    for s in keys(var.services) : s => s == "orchestrator" ? "orchestrator-events" : "${s}-commands"
  }
}

data "aws_iam_role" "lab_role" {
  name = var.lab_role_name
}

# ── Rede ─────────────────────────────────────────────────────────────────────

module "vpc" {
  source = "./modules/vpc"

  project              = var.project
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  tags                 = local.common_tags
}

# ── Registro de imagens ──────────────────────────────────────────────────────

module "ecr" {
  source = "./modules/ecr"

  project               = var.project
  services              = keys(var.services)
  image_retention_count = var.ecr_image_retention_count
  tags                  = local.common_tags
}

# ── Mensageria da saga (ADR-0006) ────────────────────────────────────────────

module "sqs" {
  source = "./modules/sqs"

  project = var.project
  queues  = var.sqs_queues
  tags    = local.common_tags
}

# ── Cluster ──────────────────────────────────────────────────────────────────

module "eks" {
  source = "./modules/eks"

  project            = var.project
  environment        = var.environment
  cluster_version    = var.eks_cluster_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  node_instance_type = var.eks_node_instance_type
  node_desired_size  = var.eks_node_desired_size
  node_min_size      = var.eks_node_min_size
  node_max_size      = var.eks_node_max_size
  lab_role_arn       = data.aws_iam_role.lab_role.arn
  tags               = local.common_tags

  node_metadata_hop_limit = var.eks_node_metadata_hop_limit
  ebs_csi_enabled         = var.eks_ebs_csi_enabled
}

# O addon do driver EBS CSI morava no modulo de observabilidade, desligado por
# padrao. Se algum ambiente o tinha ligado, o state acompanha a mudanca em vez
# de destruir e recriar o driver.
moved {
  from = module.observability[0].aws_eks_addon.ebs_csi_driver[0]
  to   = module.eks.aws_eks_addon.ebs_csi_driver[0]
}

# ── NLB interno da aplicacao ─────────────────────────────────────────────────
#
# Substitui o Service type: LoadBalancer publico do mechanical-hub.
# O AWS Load Balancer Controller exigiria IRSA, bloqueado no AWS Academy Lab;
# provisionando aqui, a criacao usa a mesma identidade que ja aplica
# VPC/EKS/ECR, sem IAM novo. Ver modules/app-lb/main.tf para o raciocinio
# completo.

module "app_lb" {
  source = "./modules/app-lb"

  project                = var.project
  environment            = var.environment
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnet_ids
  private_subnet_cidrs   = module.vpc.private_subnet_cidrs
  autoscaling_group_name = module.eks.node_group_autoscaling_group_name
  services               = var.services
  tags                   = local.common_tags

  # Cluster SG gerenciado pelo EKS: e o que esta anexado aos nodes.
  cluster_security_group_id = module.eks.cluster_security_group_id

  # Ponte de telemetria para as Lambdas (RFC-0004, etapa 3). Elas rodam na VPC
  # mas fora do cluster, entao nao alcancam o Service do coletor; um listener
  # neste mesmo NLB resolve, sem recurso de rede novo. Nulo nao cria nada.
  otlp_node_port = var.observability_enabled ? var.observability_otlp_http_node_port : null
}

# ── Observabilidade ──────────────────────────────────────────────────────────
#
# Implementa a RFC-0004: OpenTelemetry (coleta), Prometheus (metricas), Loki
# (logs), Tempo (traces) e Grafana (visualizacao), instalados no proprio
# cluster via Helm — mesmo padrao ja usado para o metrics-server.
#
# Mora neste repositorio, e nao no mechanical-hub, porque e infraestrutura de
# plataforma: existe independente da aplicacao e e consumida por ela e pelas
# Lambdas. Os outputs otlp_* sao o contrato que os dois lados usam para
# exportar telemetria.
#
# O count permite desligar a stack inteira sem apagar codigo. Vale quando o
# cluster do laboratorio esta apertado e a prioridade e ter a aplicacao no ar.

module "observability" {
  source = "./modules/observability"
  count  = var.observability_enabled ? 1 : 0

  project                = var.project
  environment            = var.environment
  cluster_name           = module.eks.cluster_name
  namespace              = var.observability_namespace
  app_namespace          = var.app_namespace
  grafana_admin_password = var.grafana_admin_password
  metrics_retention      = var.observability_metrics_retention
  logs_retention         = var.observability_logs_retention
  traces_retention       = var.observability_traces_retention
  persistence_enabled    = var.observability_persistence_enabled
  storage_class          = coalesce(module.eks.storage_class_name, "gp2")
  otlp_http_node_port    = var.observability_otlp_http_node_port
  tags                   = local.common_tags

  # Fase 4: scrape e paineis por servico, painel da saga com as filas.
  aws_region = var.aws_region
  services = {
    for s, q in local.service_consumed_queue : s => {
      queue = lookup(module.sqs.queue_names, q, "")
      dlq   = lookup(module.sqs.dlq_names, q, "")
    }
  }
  queue_names = values(module.sqs.queue_names)
  dlq_names   = values(module.sqs.dlq_names)

  # Sem isto, o Terraform tentaria instalar os charts assim que o endpoint do
  # cluster existisse — antes de haver node capaz de agendar os pods.
  depends_on = [module.eks]
}
