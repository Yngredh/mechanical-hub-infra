output "nlb_arn" {
  description = "ARN do NLB interno da aplicacao. Alvo do aws_api_gateway_vpc_link no mechanical-hub-auth."
  value       = aws_lb.app.arn
}

output "nlb_dns_name" {
  description = "DNS interno do NLB — resolve apenas de dentro da VPC (ou por quem tem um VPC Link ate ela)."
  value       = aws_lb.app.dns_name
}

output "target_group_arns" {
  description = "Target group de cada servico, atrelado a ASG dos nodes do EKS."
  value       = { for s, tg in aws_lb_target_group.app : s => tg.arn }
}

output "backend_base_urls" {
  description = "URL base (DNS do NLB + porta) de cada servico, para as integracoes via VPC Link."
  value       = { for s, cfg in var.services : s => "http://${aws_lb.app.dns_name}:${cfg.node_port}" }
}

output "otlp_backend_url" {
  description = <<-EOT
    Endereco OTLP/HTTP alcancavel de dentro da VPC, ou nulo quando o listener
    nao foi criado. E o valor de OTEL_EXPORTER_OTLP_ENDPOINT das Lambdas.
  EOT
  value       = var.otlp_node_port == null ? null : "http://${aws_lb.app.dns_name}:${var.otlp_node_port}"
}
