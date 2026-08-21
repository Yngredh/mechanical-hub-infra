variable "project" {
  description = "Nome do projeto, usado como prefixo dos recursos."
  type        = string
}

variable "environment" {
  description = "Ambiente de implantacao (production, staging)."
  type        = string
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC."
  type        = string
}

variable "availability_zones" {
  description = "AZs de implantacao. Uma por CIDR de subnet."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets publicas (uma por AZ)."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas (uma por AZ)."
  type        = list(string)
}

variable "tags" {
  description = "Tags comuns aplicadas a todos os recursos do modulo."
  type        = map(string)
}
