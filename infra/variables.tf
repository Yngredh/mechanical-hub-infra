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
  description = "Quantidade desejada de nodes."
  type        = number
  default     = 2
}

variable "eks_node_min_size" {
  description = "Quantidade minima de nodes."
  type        = number
  default     = 1
}

variable "eks_node_max_size" {
  description = "Quantidade maxima de nodes."
  type        = number
  default     = 4
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
