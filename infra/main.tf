# =============================================================================
# Infraestrutura base da plataforma Mechanical Hub
#
# Escopo deste repositorio (ADR-0004): rede (VPC), cluster de execucao (EKS) e
# registro de imagens (ECR). O banco de dados vive em `mechanical-hub-database`,
# que le vpc_id / private_subnet_ids / private_subnet_cidrs do state daqui.
# =============================================================================

locals {
  common_tags = {
    Project     = var.project
    Component   = "infra"
    Environment = var.environment
    ManagedBy   = "terraform"
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
  image_retention_count = var.ecr_image_retention_count
  tags                  = local.common_tags
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
}

# ── NLB interno da aplicacao ─────────────────────────────────────────────────
#
# Substitui o Service type: LoadBalancer publico do mechanical-hub (ver adendo da ADR-0003).
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
  node_security_group_id = module.eks.cluster_security_group_id
  autoscaling_group_name = module.eks.node_group_autoscaling_group_name
  node_port              = var.app_node_port
  health_check_path      = var.app_health_check_path
  tags                   = local.common_tags

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
  manage_ebs_csi_addon   = var.observability_manage_ebs_csi_addon
  otlp_http_node_port    = var.observability_otlp_http_node_port
  tags                   = local.common_tags

  # Sem isto, o Terraform tentaria instalar os charts assim que o endpoint do
  # cluster existisse — antes de haver node capaz de agendar os pods.
  depends_on = [module.eks]
}
