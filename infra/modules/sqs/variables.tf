variable "project" {
  description = "Nome do projeto, usado como prefixo das filas."
  type        = string
}

variable "queues" {
  description = <<-EOT
    Chaves das filas. Cada uma gera <project>-<chave>.fifo e a DLQ
    <project>-<chave>-dlq.fifo (infrastructure.md §3). As chaves sao o
    contrato com os servicos (outputs sqs_*).
  EOT
  type        = list(string)

  validation {
    condition     = length(var.queues) > 0 && length(var.queues) == length(distinct(var.queues))
    error_message = "queues precisa ter ao menos um item, sem repeticao."
  }
}

variable "visibility_timeout_seconds" {
  description = "Tempo em que a mensagem recebida fica invisivel aos outros consumidores."
  type        = number
  default     = 30
}

variable "receive_wait_time_seconds" {
  description = "Long polling: quanto o ReceiveMessage espera por mensagem. 20 e o maximo e reduz chamadas vazias."
  type        = number
  default     = 20
}

variable "message_retention_seconds" {
  description = "Retencao das filas de origem. Padrao: 4 dias."
  type        = number
  default     = 345600
}

variable "dlq_message_retention_seconds" {
  description = "Retencao das DLQs. Padrao: 14 dias (o maximo do SQS)."
  type        = number
  default     = 1209600
}

variable "max_receive_count" {
  description = "Entregas sem confirmacao antes de a mensagem ir para a DLQ (failure_handling.md §3)."
  type        = number
  default     = 6
}

variable "tags" {
  description = "Tags comuns aplicadas a todos os recursos do modulo."
  type        = map(string)
}

variable "dlq_alarms_enabled" {
  description = "Cria um alarme do CloudWatch por DLQ (mensagens visiveis > 0 em 5 min)."
  type        = bool
  default     = true
}
