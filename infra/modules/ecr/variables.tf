variable "project" {
  description = "Nome do projeto. Cada repositorio criado e <project>/<servico>."
  type        = string
}

variable "services" {
  description = "Servicos que publicam imagem. Um repositorio ECR por item."
  type        = list(string)

  validation {
    condition     = length(var.services) > 0 && length(var.services) == length(distinct(var.services))
    error_message = "services precisa ter ao menos um item, sem repeticao."
  }
}

variable "image_retention_count" {
  description = "Quantidade de imagens com tag mantidas antes da limpeza."
  type        = number
}

variable "tags" {
  description = "Tags comuns aplicadas a todos os recursos do modulo."
  type        = map(string)
}
