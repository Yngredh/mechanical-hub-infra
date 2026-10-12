output "queue_urls" {
  description = "URL de cada fila, por chave."
  value       = { for k, q in aws_sqs_queue.this : k => q.url }
}

output "queue_arns" {
  description = "ARN de cada fila, por chave."
  value       = { for k, q in aws_sqs_queue.this : k => q.arn }
}

output "queue_names" {
  description = "Nome de cada fila, por chave. Usado nas consultas do CloudWatch."
  value       = { for k, q in aws_sqs_queue.this : k => q.name }
}

output "dlq_urls" {
  description = "URL de cada DLQ, por chave da fila de origem."
  value       = { for k, q in aws_sqs_queue.dlq : k => q.url }
}

output "dlq_arns" {
  description = "ARN de cada DLQ, por chave da fila de origem."
  value       = { for k, q in aws_sqs_queue.dlq : k => q.arn }
}

output "dlq_names" {
  description = "Nome de cada DLQ, por chave da fila de origem. Usado nas consultas do CloudWatch."
  value       = { for k, q in aws_sqs_queue.dlq : k => q.name }
}
