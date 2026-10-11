variable "project" {
  description = "Nome do projeto, usado como prefixo dos recursos."
  type        = string
}

variable "environment" {
  description = "Ambiente de implantacao (production, staging)."
  type        = string
}

variable "cluster_version" {
  description = "Versao do Kubernetes do cluster."
  type        = string
}

variable "vpc_id" {
  description = "VPC onde o cluster e os security groups sao criados."
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets privadas onde ficam o control plane e os nodes."
  type        = list(string)
}

variable "node_instance_type" {
  description = "Tipo de instancia EC2 dos nodes."
  type        = string
}

variable "node_desired_size" {
  description = "Quantidade desejada de nodes."
  type        = number
}

variable "node_min_size" {
  description = "Quantidade minima de nodes."
  type        = number
}

variable "node_max_size" {
  description = "Quantidade maxima de nodes."
  type        = number
}

variable "lab_role_arn" {
  description = "ARN da role usada pelo cluster e pelos nodes (LabRole no AWS Academy)."
  type        = string
}

variable "tags" {
  description = "Tags comuns aplicadas a todos os recursos do modulo."
  type        = map(string)
}

variable "node_metadata_hop_limit" {
  description = <<-EOT
    http_put_response_hop_limit do IMDSv2 nos nodes. Precisa ser >= 2 para os
    pods (SQS, driver EBS CSI) lerem as credenciais da LabRole pelo IMDS.
  EOT
  type        = number
  default     = 2

  validation {
    condition     = var.node_metadata_hop_limit >= 2 && var.node_metadata_hop_limit <= 64
    error_message = "O hop limit precisa ser >= 2: com 1, a resposta do IMDS nao chega aos pods."
  }
}

variable "ebs_csi_enabled" {
  description = <<-EOT
    Instala o addon aws-ebs-csi-driver (sem IRSA) e cria a StorageClass
    var.storage_class_name. Necessario para PersistentVolumeClaims, como o do
    MongoDB.
  EOT
  type        = bool
  default     = true
}

variable "storage_class_name" {
  description = "Nome da StorageClass gp3 criada quando var.ebs_csi_enabled = true."
  type        = string
  default     = "gp3"
}
