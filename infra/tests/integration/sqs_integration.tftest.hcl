# Testes de integracao do modulo SQS contra o LocalStack: cria as filas e DLQs,
# confere os atributos lidos de volta da API e destroi tudo ao final (o
# `terraform test` desfaz o apply sozinho).
#
#   docker run --rm -d -p 4566:4566 localstack/localstack
#   terraform init -test-directory=tests/integration
#   terraform test -test-directory=tests/integration -filter=tests/integration/sqs_integration.tftest.hcl
#
# Nao rodam no CI: dependem de um LocalStack acessivel em localhost:4566.

provider "aws" {
  access_key = "test"
  secret_key = "test"
  region     = "us-east-1"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    sqs        = "http://localhost:4566"
    cloudwatch = "http://localhost:4566"
    sts        = "http://localhost:4566"
  }
}

variables {
  project = "mhub-test"
  queues  = ["orders-commands", "stock-commands", "billing-commands", "orchestrator-events"]
  tags    = { ManagedBy = "terraform", Env = "test" }
}

run "filas_e_dlqs_sao_criadas" {
  command = apply

  module {
    source = "./modules/sqs"
  }

  assert {
    condition     = length(output.queue_urls) == 4 && length(output.dlq_urls) == 4
    error_message = "Esperadas 4 filas e 4 DLQs criadas."
  }

  assert {
    condition     = alltrue([for url in concat(values(output.queue_urls), values(output.dlq_urls)) : endswith(url, ".fifo")])
    error_message = "Toda fila criada precisa ser FIFO (.fifo)."
  }
}

# Segundo run sobre o mesmo state: o plan faz refresh e os atributos abaixo
# vem da API do SQS, nao do que foi enviado. E o que pega um atributo que o
# provider aceita mas o servico ignora.
run "atributos_lidos_da_api_conferem" {
  command = plan

  module {
    source = "./modules/sqs"
  }

  assert {
    condition = alltrue([for q in aws_sqs_queue.this :
      q.visibility_timeout_seconds == 30 && q.message_retention_seconds == 345600 &&
      q.receive_wait_time_seconds == 20 && q.fifo_queue && q.content_based_deduplication == false
    ])
    error_message = "Atributos das filas divergem da spec (visibility 30, retencao 4 d, long polling 20, FIFO sem dedup por conteudo)."
  }

  assert {
    condition     = alltrue([for q in aws_sqs_queue.dlq : q.message_retention_seconds == 1209600 && q.fifo_queue])
    error_message = "DLQs precisam ser FIFO com retencao de 14 dias."
  }

  assert {
    condition = alltrue([for k, q in aws_sqs_queue.this :
      jsondecode(q.redrive_policy).maxReceiveCount == 6 &&
      jsondecode(q.redrive_policy).deadLetterTargetArn == aws_sqs_queue.dlq[k].arn
    ])
    error_message = "Redrive policy divergente: cada fila vai para a sua DLQ apos 6 recebimentos."
  }

  assert {
    condition = alltrue([for k, p in aws_sqs_queue_redrive_allow_policy.dlq :
      jsondecode(p.redrive_allow_policy).sourceQueueArns == [aws_sqs_queue.this[k].arn]
    ])
    error_message = "Cada DLQ precisa aceitar redrive so da sua fila de origem."
  }
}
