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
# Substitui o Service type: LoadBalancer publico do mechanical-hub (item 47).
# O AWS Load Balancer Controller exigiria IRSA, bloqueado no AWS Academy Lab;
# provisionando aqui, a criacao usa a mesma identidade que ja aplica
# VPC/EKS/ECR, sem IAM novo. Ver modules/app-lb/main.tf para o raciocinio
# completo.

module "app_lb" {
  source = "./modules/app-lb"

  project                 = var.project
  environment             = var.environment
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_subnet_ids
  private_subnet_cidrs    = module.vpc.private_subnet_cidrs
  node_security_group_id  = module.eks.node_security_group_id
  autoscaling_group_name  = module.eks.node_group_autoscaling_group_name
  node_port               = var.app_node_port
  health_check_path       = var.app_health_check_path
  tags                    = local.common_tags
}
