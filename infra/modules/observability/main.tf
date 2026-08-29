# =============================================================================
# Stack de observabilidade — OpenTelemetry, Prometheus, Loki, Tempo e Grafana
#
# Implementa a RFC-0004 (mechanical-hub/docs/architecture/rfc/
# 0004-observabilidade-opentelemetry-prometheus-grafana.md).
#
# Decisoes que vem da RFC e nao devem ser revertidas sem revisa-la:
#
#   1. Armazenamento local (emptyDir por padrao, PVC opcional) em vez de S3.
#      Loki e Tempo em modo S3 exigiriam uma IAM role via IRSA — exatamente o
#      guardrail do AWS Academy Lab que ja derrubou o AWS Load Balancer
#      Controller (ver modules/app-lb/main.tf). Nenhum recurso deste modulo
#      cria IAM.
#
#   2. Dashboards e regras de alerta sao codigo versionado, nunca criados pela
#      UI do Grafana. Dashboards viram ConfigMap com a label
#      `grafana_dashboard: "1"`, que o sidecar do chart carrega sozinho; as
#      regras vao em `additionalPrometheusRulesMap` nos values do
#      kube-prometheus-stack. Depois de um reset do Lab, `terraform apply`
#      devolve tudo — o que se perde e o historico coletado, nao a configuracao.
#
#   3. As regras NAO usam o recurso `kubernetes_manifest` para criar
#      PrometheusRule. Esse recurso exige que a CRD ja exista no cluster no
#      momento do *plan*, o que quebra o primeiro apply (a CRD so nasce com o
#      chart). `additionalPrometheusRulesMap` resolve isso sem ordenacao.
#
# Dimensionamento: os requests/limits abaixo sao apertados de proposito para
# caber em nodes t3.medium ao lado da aplicacao. Somados, os requests deste
# modulo ficam em torno de 0,6 vCPU e 1,8 GiB.
# =============================================================================

locals {
  namespace = var.namespace

  # Nomes dos releases. Sao usados para montar os enderecos de servico logo
  # abaixo — o chart do kube-prometheus-stack deriva o nome dos Services do
  # nome do release, entao mudar um exige mudar o outro junto.
  kube_prometheus_stack_release = "kube-prometheus-stack"
  loki_release                  = "loki"
  tempo_release                 = "tempo"
  otel_collector_release        = "otel-collector"
  otel_logs_agent_release       = "otel-logs-agent"

  # O chart do coletor sufixa o nome do release com o nome do chart.
  otel_collector_service = "${local.otel_collector_release}-opentelemetry-collector"

  # Enderecos internos (DNS do cluster). Se algum Service nascer com outro
  # nome, e aqui — num lugar so — que se corrige.
  prometheus_url  = "http://${local.kube_prometheus_stack_release}-prometheus.${local.namespace}.svc.cluster.local:9090"
  loki_url        = "http://${local.loki_release}.${local.namespace}.svc.cluster.local:3100"
  tempo_http_url  = "http://${local.tempo_release}.${local.namespace}.svc.cluster.local:3100"
  tempo_otlp_grpc = "${local.tempo_release}.${local.namespace}.svc.cluster.local:4317"

  # UIDs fixos dos datasources. Os JSON dos dashboards referenciam estes
  # valores literalmente, entao eles precisam ser estaveis.
  prometheus_datasource_uid = "mh-prometheus"
  loki_datasource_uid       = "mh-loki"
  tempo_datasource_uid      = "mh-tempo"

  labels = {
    "app.kubernetes.io/part-of"    = var.project
    "app.kubernetes.io/managed-by" = "terraform"
    "mechanical-hub/component"     = "observability"
  }
}

# ── Namespace ────────────────────────────────────────────────────────────────
#
# Criado aqui, e nao por `create_namespace` do helm_release: assim os
# ConfigMaps de dashboard podem ser criados no mesmo namespace sem depender da
# ordem em que o Helm resolve os releases.

resource "kubernetes_namespace" "observability" {
  metadata {
    name   = local.namespace
    labels = local.labels
  }
}

# ── Prometheus + Grafana + Alertmanager + exporters ──────────────────────────
#
# Um unico chart entrega: Prometheus Operator, Prometheus, Alertmanager,
# Grafana (com o sidecar de dashboards), node-exporter e kube-state-metrics —
# que sao a fonte das metricas de CPU/memoria exigidas pela fase.

resource "helm_release" "kube_prometheus_stack" {
  name       = local.kube_prometheus_stack_release
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  version    = var.kube_prometheus_stack_chart_version

  # Os CRDs do Prometheus Operator sao grandes; o default de 300s estoura em
  # cluster pequeno.
  timeout = var.helm_timeout_seconds

  values = [
    templatefile("${path.module}/values/kube-prometheus-stack.yaml.tftpl", {
      cluster_name              = var.cluster_name
      environment               = var.environment
      grafana_admin_password    = var.grafana_admin_password
      metrics_retention         = var.metrics_retention
      persistence_enabled       = var.persistence_enabled
      storage_class             = var.storage_class
      prometheus_storage_size   = var.prometheus_storage_size
      prometheus_url            = local.prometheus_url
      loki_url                  = local.loki_url
      tempo_http_url            = local.tempo_http_url
      prometheus_datasource_uid = local.prometheus_datasource_uid
      loki_datasource_uid       = local.loki_datasource_uid
      tempo_datasource_uid      = local.tempo_datasource_uid
      alert_latency_seconds     = var.alert_api_latency_seconds
      alert_error_rate          = var.alert_api_error_rate
      app_namespace             = var.app_namespace
    })
  ]
}

# ── Loki — logs ──────────────────────────────────────────────────────────────
#
# Modo SingleBinary com armazenamento em filesystem. Os caches (memcached), o
# gateway nginx e o canary vem ligados por padrao no chart e sao desligados
# aqui: para o volume deste projeto eles so consomem espaco no node.

resource "helm_release" "loki" {
  name       = local.loki_release
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  version    = var.loki_chart_version

  timeout = var.helm_timeout_seconds

  values = [
    templatefile("${path.module}/values/loki.yaml.tftpl", {
      logs_retention      = var.logs_retention
      persistence_enabled = var.persistence_enabled
      storage_class       = var.storage_class
      storage_size        = var.loki_storage_size
    })
  ]
}

# ── Tempo — traces ───────────────────────────────────────────────────────────
#
# Chart monolitico (grafana/tempo), backend `local`. O tempo-distributed seria
# a escolha de producao, mas exige object storage — ou seja, IRSA.

resource "helm_release" "tempo" {
  name       = local.tempo_release
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  namespace  = kubernetes_namespace.observability.metadata[0].name

  # Nulo = deixa o Helm resolver a ultima versao publicada. Ver
  # var.tempo_chart_version para o porque de este ser o unico sem pin.
  version = var.tempo_chart_version

  timeout = var.helm_timeout_seconds

  values = [
    templatefile("${path.module}/values/tempo.yaml.tftpl", {
      traces_retention    = var.traces_retention
      persistence_enabled = var.persistence_enabled
      storage_class       = var.storage_class
      storage_size        = var.tempo_storage_size
    })
  ]
}

# ── OpenTelemetry Collector — porta de entrada unica da telemetria ───────────
#
# A aplicacao (Spring Boot) e as Lambdas do mechanical-hub-auth exportam OTLP
# para ca; daqui a telemetria se divide entre Prometheus (metricas via remote
# write), Loki (logs via OTLP nativo) e Tempo (traces via OTLP).
#
# Ter um coletor no meio, em vez de cada servico falar direto com cada backend,
# e o que permite trocar qualquer backend sem tocar em codigo de aplicacao —
# a portabilidade que motivou escolher OpenTelemetry na RFC-0004.

resource "helm_release" "otel_collector" {
  name       = local.otel_collector_release
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  version    = var.otel_collector_chart_version

  timeout = var.helm_timeout_seconds

  values = [
    templatefile("${path.module}/values/otel-collector.yaml.tftpl", {
      cluster_name    = var.cluster_name
      environment     = var.environment
      prometheus_url  = local.prometheus_url
      loki_url        = local.loki_url
      tempo_otlp_grpc = local.tempo_otlp_grpc
      http_node_port  = var.otlp_http_node_port
    })
  ]

  # O remote write vai para o Prometheus provisionado pelo chart acima: sem
  # ele no ar, o coletor sobe reclamando de destino inalcancavel.
  depends_on = [helm_release.kube_prometheus_stack]
}

# ── Coletor OpenTelemetry (agente) — logs dos pods ───────────────────────────
#
# Segundo coletor, em DaemonSet. O de cima so recebe o que lhe e enviado por
# OTLP; log nao funciona assim — a aplicacao escreve em stdout e o kubelet grava
# em arquivo no disco do node, entao e preciso um pod em cada node para ler.
#
# E a topologia padrao do OpenTelemetry em Kubernetes: agente coleta do node,
# gateway concentra o que chega por OTLP.

resource "helm_release" "otel_logs_agent" {
  name       = local.otel_logs_agent_release
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  version    = var.otel_collector_chart_version

  timeout = var.helm_timeout_seconds

  values = [
    templatefile("${path.module}/values/otel-logs-agent.yaml.tftpl", {
      cluster_name = var.cluster_name
      environment  = var.environment
      loki_url     = local.loki_url
    })
  ]

  depends_on = [helm_release.loki]
}

# ── Dashboards como codigo ───────────────────────────────────────────────────
#
# O sidecar do Grafana (kiwigrid/k8s-sidecar, embutido no chart) observa a API
# do Kubernetes procurando ConfigMaps com a label abaixo, escreve o conteudo
# num volume compartilhado e o Grafana recarrega sozinho — sem reiniciar pod e
# sem ninguem abrir a UI.
#
# Para adicionar um dashboard: exporte o JSON pela UI do Grafana
# (Dashboard settings -> JSON Model), salve em dashboards/ e adicione o nome
# do arquivo ao for_each. Nada mais.

resource "kubernetes_config_map" "grafana_dashboards" {
  for_each = toset(var.dashboard_files)

  metadata {
    name      = "grafana-dashboard-${trimsuffix(each.value, ".json")}"
    namespace = kubernetes_namespace.observability.metadata[0].name

    labels = merge(local.labels, {
      grafana_dashboard = "1"
    })
  }

  data = {
    (each.value) = file("${path.module}/dashboards/${each.value}")
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

# ── Driver de volume (opcional) ──────────────────────────────────────────────
#
# So entra em cena quando var.persistence_enabled = true. A partir do
# Kubernetes 1.27 o provisionador EBS in-tree deixou de existir: sem o driver
# CSI instalado, qualquer PersistentVolumeClaim fica pendente para sempre.
#
# O addon e criado SEM service_account_role_arn de proposito — assim o driver
# usa as credenciais do instance profile dos nodes (a LabRole), em vez de uma
# IAM role via IRSA, que o Lab nao deixa criar. Se ainda assim falhar por
# permissao, o caminho e voltar var.persistence_enabled para false: o
# armazenamento volta a ser efemero e a stack sobe do mesmo jeito.

resource "aws_eks_addon" "ebs_csi_driver" {
  count = var.manage_ebs_csi_addon ? 1 : 0

  cluster_name = var.cluster_name
  addon_name   = "aws-ebs-csi-driver"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}
