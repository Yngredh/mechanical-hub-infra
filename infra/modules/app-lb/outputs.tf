output "nlb_arn" {
  description = "ARN do NLB interno da aplicacao. Alvo do aws_api_gateway_vpc_link no mechanical-hub-auth."
  value       = aws_lb.app.arn
}

output "nlb_dns_name" {
  description = "DNS interno do NLB — resolve apenas de dentro da VPC (ou por quem tem um VPC Link ate ela)."
  value       = aws_lb.app.dns_name
}

output "target_group_arn" {
  description = "Target group anexado ao NLB, atrelado a ASG dos nodes do EKS."
  value       = aws_lb_target_group.app.arn
}
