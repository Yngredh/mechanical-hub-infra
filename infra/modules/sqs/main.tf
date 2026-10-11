# =============================================================================
# Mensageria da saga (Fase 4, ADR-0006)
#
# Uma fila FIFO por destino de mensagem — comandos para orders, stock e
# billing, eventos para o orchestrator — cada uma com sua DLQ FIFO.
#
# Por que FIFO: a saga depende da ordem dos passos de um mesmo pedido. Os
# servicos publicam com MessageGroupId = id da saga, o que preserva a ordem por
# saga e ainda deixa sagas diferentes andarem em paralelo.
#
# Por que content_based_deduplication = false: os servicos enviam
# MessageDeduplicationId = eventId (outbox). Deduplicar pelo corpo trataria
# como duplicada uma retentativa legitima com payload igual, e deixaria passar
# a mesma mensagem reenviada com um campo de data diferente.
#
# Sem VPC endpoint de proposito: ele cobra por hora e o trafego ja sai pelo NAT
# existente. As credenciais vem da LabRole dos nodes, pelo IMDS (sem IRSA).
# =============================================================================

locals {
  name_prefix = "${var.project}-${var.environment}"
}

# ── DLQs ─────────────────────────────────────────────────────────────────────
#
# Retencao maior que a da fila de origem: a mensagem precisa continuar na DLQ
# tempo suficiente para alguem investigar e reprocessar (redrive pelo console).

resource "aws_sqs_queue" "dlq" {
  for_each = toset(var.queues)

  name                        = "${local.name_prefix}-${each.key}-dlq.fifo"
  fifo_queue                  = true
  content_based_deduplication = false
  message_retention_seconds   = var.dlq_message_retention_seconds
  sqs_managed_sse_enabled     = true

  tags = merge(var.tags, { Queue = each.key, Role = "dlq" })
}

# ── Filas ────────────────────────────────────────────────────────────────────

resource "aws_sqs_queue" "this" {
  for_each = toset(var.queues)

  name                        = "${local.name_prefix}-${each.key}.fifo"
  fifo_queue                  = true
  content_based_deduplication = false
  visibility_timeout_seconds  = var.visibility_timeout_seconds
  receive_wait_time_seconds   = var.receive_wait_time_seconds
  message_retention_seconds   = var.message_retention_seconds
  sqs_managed_sse_enabled     = true

  # Depois de max_receive_count entregas sem confirmacao, a mensagem vai para
  # a DLQ em vez de travar o grupo FIFO inteiro (failure_handling.md §3).
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(var.tags, { Queue = each.key, Role = "queue" })
}

# Restringe cada DLQ a sua fila de origem. Alem de impedir que outra fila a
# use por engano, e o que habilita o redrive nativo (DLQ -> origem) pelo
# console. Recurso separado porque a DLQ nao pode referenciar a fila de origem
# no proprio bloco sem criar um ciclo (a origem ja referencia a DLQ).
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  for_each = toset(var.queues)

  queue_url = aws_sqs_queue.dlq[each.key].id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.this[each.key].arn]
  })
}
