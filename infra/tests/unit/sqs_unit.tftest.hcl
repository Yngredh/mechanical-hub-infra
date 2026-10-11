# Testes unitarios do modulo SQS.
# Usa mock_provider — nao exige credenciais AWS nem LocalStack.
# Execute a partir de infra/:
#   terraform test -test-directory=tests/unit -filter=tests/unit/sqs_unit.tftest.hcl
#
# Os runs que leem a redrive policy usam `command = apply` contra o provider
# mockado: a politica referencia o ARN da DLQ, que e computado e fica
# desconhecido no plan. Nada e criado na AWS.

mock_provider "aws" {
  mock_resource "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws:sqs:us-east-1:123456789012:mock.fifo"
      url = "https://sqs.us-east-1.amazonaws.com/123456789012/mock.fifo"
    }
  }
}

variables {
  project = "mechanical-hub"
  queues  = ["orders-commands", "stock-commands", "billing-commands", "orchestrator-events"]
  tags    = { ManagedBy = "terraform" }
}

run "quatro_filas_fifo_e_quatro_dlqs" {
  command = plan

  module {
    source = "./modules/sqs"
  }

  assert {
    condition     = length(aws_sqs_queue.this) == 4 && length(aws_sqs_queue.dlq) == 4
    error_message = "Esperadas 4 filas e 4 DLQs."
  }

  assert {
    condition     = alltrue([for q in concat(values(aws_sqs_queue.this), values(aws_sqs_queue.dlq)) : q.fifo_queue])
    error_message = "Filas e DLQs precisam ser FIFO (a DLQ de uma FIFO tambem e FIFO)."
  }

  # Nomes de infrastructure.md §3 — os servicos dependem deles.
  assert {
    condition     = aws_sqs_queue.this["orchestrator-events"].name == "mechanical-hub-orchestrator-events.fifo"
    error_message = "A fila precisa se chamar <project>-<chave>.fifo."
  }

  assert {
    condition     = aws_sqs_queue.dlq["orders-commands"].name == "mechanical-hub-orders-commands-dlq.fifo"
    error_message = "A DLQ precisa se chamar <project>-<chave>-dlq.fifo."
  }
}

run "parametros_das_filas" {
  command = plan

  module {
    source = "./modules/sqs"
  }

  # Os servicos mandam MessageDeduplicationId = eventId. Deduplicar pelo corpo
  # trocaria esse contrato por outro, sem ninguem perceber.
  assert {
    condition     = alltrue([for q in concat(values(aws_sqs_queue.this), values(aws_sqs_queue.dlq)) : q.content_based_deduplication == false])
    error_message = "content_based_deduplication precisa ser false."
  }

  assert {
    condition = alltrue([for q in aws_sqs_queue.this :
      q.visibility_timeout_seconds == 30 && q.receive_wait_time_seconds == 20 && q.message_retention_seconds == 345600
    ])
    error_message = "Filas: visibility 30 s, long polling 20 s e retencao de 4 dias."
  }

  assert {
    condition     = alltrue([for q in aws_sqs_queue.dlq : q.message_retention_seconds == 1209600])
    error_message = "DLQs: retencao de 14 dias."
  }
}

run "redrive_para_a_propria_dlq_apos_6_recebimentos" {
  command = apply

  module {
    source = "./modules/sqs"
  }

  assert {
    condition     = alltrue([for q in aws_sqs_queue.this : jsondecode(q.redrive_policy).maxReceiveCount == 6])
    error_message = "maxReceiveCount precisa ser 6 (1 tentativa + 5 retries)."
  }

  assert {
    condition = alltrue([for k, q in aws_sqs_queue.this :
      jsondecode(q.redrive_policy).deadLetterTargetArn == aws_sqs_queue.dlq[k].arn
    ])
    error_message = "Cada fila precisa apontar para a sua DLQ."
  }

  # A DLQ aceita mensagens so da fila de origem — e o que habilita o redrive
  # nativo pelo console.
  assert {
    condition = alltrue([for k, p in aws_sqs_queue_redrive_allow_policy.dlq :
      jsondecode(p.redrive_allow_policy).redrivePermission == "byQueue" &&
      jsondecode(p.redrive_allow_policy).sourceQueueArns == [aws_sqs_queue.this[k].arn]
    ])
    error_message = "redrive_allow_policy da DLQ precisa ser byQueue, restrita a fila de origem."
  }
}

run "alarme_por_dlq" {
  command = plan

  module {
    source = "./modules/sqs"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.dlq_not_empty) == 4
    error_message = "Cada DLQ precisa de um alarme."
  }

  assert {
    condition = alltrue([for a in aws_cloudwatch_metric_alarm.dlq_not_empty :
      a.metric_name == "ApproximateNumberOfMessagesVisible" && a.threshold == 0 &&
      a.comparison_operator == "GreaterThanThreshold" && a.period == 300
    ])
    error_message = "O alarme e: mensagens visiveis > 0 em 5 minutos."
  }
}
