output "namespace" {
  description = "Namespace onde a stack de observabilidade esta instalada."
  value       = kubernetes_namespace.observability.metadata[0].name
}

output "grafana_service_name" {
  description = <<-EOT
    Service do Grafana. Nao ha Ingress: o acesso e por port-forward, o que
    evita expor a interface na internet a partir de um cluster de laboratorio.

      kubectl -n <namespace> port-forward svc/<este valor> 3000:80
  EOT
  value       = "${local.kube_prometheus_stack_release}-grafana"
}

output "grafana_port_forward_command" {
  description = "Comando pronto para abrir o Grafana em http://localhost:3000 (usuario: admin)."
  value       = "kubectl -n ${local.namespace} port-forward svc/${local.kube_prometheus_stack_release}-grafana 3000:80"
}

output "prometheus_url" {
  description = "Endereco interno do Prometheus, no DNS do cluster."
  value       = local.prometheus_url
}

output "loki_url" {
  description = "Endereco interno do Loki, no DNS do cluster."
  value       = local.loki_url
}

output "tempo_url" {
  description = "Endereco interno do Tempo (API HTTP), no DNS do cluster."
  value       = local.tempo_http_url
}

# ── Contrato com os repositorios instrumentados ──────────────────────────────
#
# Enderecos que a aplicacao principal (mechanical-hub) precisa conhecer para
# exportar telemetria. Sao interface publica do modulo, no mesmo espirito de
# app_backend_base_url.
#
# ATENCAO — estes enderecos so resolvem DE DENTRO do cluster. As Lambdas do
# mechanical-hub-auth rodam na VPC, mas fora do Kubernetes: elas nao enxergam
# o DNS interno do cluster e nao conseguem usar os valores abaixo. Fechar esse
# caminho e trabalho da etapa 3 do plano de observabilidade; a preparacao
# possivel aqui e var.otlp_http_node_port, que expoe o coletor num NodePort
# alcancavel por um listener do NLB interno.

output "otlp_grpc_endpoint" {
  description = "Endpoint OTLP/gRPC do coletor. Valor de OTEL_EXPORTER_OTLP_ENDPOINT para cargas dentro do cluster."
  value       = "http://${local.otel_collector_service}.${local.namespace}.svc.cluster.local:4317"
}

output "otlp_http_endpoint" {
  description = "Endpoint OTLP/HTTP do coletor, para cargas dentro do cluster."
  value       = "http://${local.otel_collector_service}.${local.namespace}.svc.cluster.local:4318"
}

output "otlp_http_node_port" {
  description = <<-EOT
    NodePort do endpoint OTLP/HTTP, ou nulo quando o Service e ClusterIP.

    Quando definido, e o contrato para as Lambdas alcancarem o coletor: basta
    um listener nessa porta no NLB interno (modulo app-lb), do mesmo jeito que
    a porta 30080 ja atende a aplicacao.
  EOT
  value       = var.otlp_http_node_port
}

output "otel_collector_service_name" {
  description = "Nome do Service do coletor OpenTelemetry."
  value       = local.otel_collector_service
}
