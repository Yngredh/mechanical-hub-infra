variable "project" {
  description = "Nome do projeto. O repositorio criado e <project>/api."
  type        = string
}

variable "image_retention_count" {
  description = "Quantidade de imagens com tag mantidas antes da limpeza."
  type        = number
}

variable "tags" {
  description = "Tags comuns aplicadas a todos os recursos do modulo."
  type        = map(string)
}
