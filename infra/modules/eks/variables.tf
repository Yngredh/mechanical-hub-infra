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
