variable "project" {
  description = "Nome do projeto, usado como prefixo e nas labels dos recursos."
  type        = string
}

variable "environment" {
  description = "Ambiente de implantacao (production, staging). Vira label de recurso na telemetria."
  type        = string
}

variable "cluster_name" {
  description = <<-EOT
    Nome do cluster EKS. Usado como label `cluster` na telemetria e como alvo
    do addon do driver EBS, quando habilitado.
  EOT
  type        = string
}

variable "namespace" {
  description = "Namespace onde toda a stack de observabilidade e instalada."
  type        = string
  default     = "monitoring"
}

variable "app_namespace" {
  description = <<-EOT
    Namespace onde a aplicacao principal (mechanical-hub) roda. As regras de
    alerta olham para os pods deste namespace.
  EOT
  type        = string
  default     = "production"
}

variable "tags" {
  description = "Tags comuns aplicadas aos recursos AWS do modulo."
  type        = map(string)
  default     = {}
}

# ── Versoes dos charts ───────────────────────────────────────────────────────
#
# Sao variaveis, e nao literais no main.tf, por um motivo pratico: se uma
# versao sair do ar ou apresentar regressao, a correcao e uma linha no tfvars
# em vez de uma alteracao no modulo.

variable "kube_prometheus_stack_chart_version" {
  description = "Versao do chart prometheus-community/kube-prometheus-stack."
  type        = string
  default     = "86.1.0"
}

variable "loki_chart_version" {
  description = "Versao do chart grafana/loki."
  type        = string
  default     = "7.1.0"
}

variable "tempo_chart_version" {
  description = <<-EOT
    Versao do chart grafana/tempo. Nulo deixa o Helm resolver a ultima
    publicada.

    E o unico chart sem pin: a versao publicada nao pode ser confirmada no
    momento em que este modulo foi escrito. Para fixar (recomendado antes da
    entrega), rode `helm search repo grafana/tempo --versions | head` e
    informe o valor aqui.
  EOT
  type        = string
  default     = null
}

variable "otel_collector_chart_version" {
  description = "Versao do chart open-telemetry/opentelemetry-collector."
  type        = string
  default     = "0.159.0"
}

variable "otlp_http_node_port" {
  description = <<-EOT
    NodePort para o endpoint OTLP/HTTP do coletor. Nulo mantem o Service como
    ClusterIP (alcancavel so de dentro do cluster).

    Existe porque as Lambdas do mechanical-hub-auth rodam na VPC mas fora do
    Kubernetes: elas nao resolvem o DNS interno do cluster. Definindo um
    NodePort aqui, um listener no NLB interno (modulo app-lb) leva a
    telemetria delas ate o coletor — mesmo padrao ja usado na porta 30080 da
    aplicacao. Fica desligado por padrao (null = nada criado); com as Lambdas
    do mechanical-hub-auth ja instrumentadas (RFC-0004), definir esta porta e o
    que liga a telemetria delas — sem ela, o auth sobe com telemetria
    desligada, sem erro (conferir o output telemetry_enabled no apply do auth).
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.otlp_http_node_port == null || try(var.otlp_http_node_port >= 30000 && var.otlp_http_node_port <= 32767, false)
    error_message = "NodePort precisa estar na faixa 30000-32767."
  }
}

variable "helm_timeout_seconds" {
  description = <<-EOT
    Tempo maximo de espera por release. O default do provider (300s) e curto
    para os CRDs do Prometheus Operator em cluster pequeno.
  EOT
  type        = number
  default     = 900
}

# ── Retencao ─────────────────────────────────────────────────────────────────

variable "metrics_retention" {
  description = <<-EOT
    Retencao das metricas no Prometheus. Precisa cobrir mais de um dia para o
    painel de volume diario de OS mostrar tendencia — exigencia da Fase 3.
  EOT
  type        = string
  default     = "7d"
}

variable "logs_retention" {
  description = "Retencao dos logs no Loki (formato de duracao do Loki, ex: 168h)."
  type        = string
  default     = "168h"
}

variable "traces_retention" {
  description = "Retencao dos traces no Tempo (formato de duracao, ex: 48h)."
  type        = string
  default     = "48h"
}

# ── Armazenamento ────────────────────────────────────────────────────────────

variable "persistence_enabled" {
  description = <<-EOT
    Liga volumes persistentes (PVC) para Prometheus, Loki e Tempo.

    Falso por padrao — e a configuracao que sobe sem nenhuma dependencia extra
    no AWS Academy Lab. Com emptyDir, a telemetria vive no pod: uma reinicia-
    cao do pod zera o historico. Para a Fase 3 isso e aceitavel (a RFC-0004 ja
    registra que o historico nao sobrevive a um reset do Lab; o que sobrevive
    e a configuracao, que e codigo).

    Ligar exige uma StorageClass funcional no cluster. A partir do Kubernetes
    1.27 isso significa o driver EBS CSI instalado — ver
    var.manage_ebs_csi_addon.
  EOT
  type        = bool
  default     = false
}

variable "manage_ebs_csi_addon" {
  description = <<-EOT
    Instala o addon aws-ebs-csi-driver no cluster, sem IRSA (o driver usa o
    instance profile dos nodes). So faz sentido junto com
    var.persistence_enabled = true.

    Falso por padrao para nao introduzir, no caminho comum, uma dependencia
    que pode esbarrar nos guardrails de IAM do laboratorio.
  EOT
  type        = bool
  default     = false
}

variable "storage_class" {
  description = "StorageClass usada pelos PVCs quando var.persistence_enabled = true."
  type        = string
  default     = "gp2"
}

variable "prometheus_storage_size" {
  description = "Tamanho do volume do Prometheus quando a persistencia esta ligada."
  type        = string
  default     = "10Gi"
}

variable "loki_storage_size" {
  description = "Tamanho do volume do Loki quando a persistencia esta ligada."
  type        = string
  default     = "10Gi"
}

variable "tempo_storage_size" {
  description = "Tamanho do volume do Tempo quando a persistencia esta ligada."
  type        = string
  default     = "5Gi"
}

# ── Grafana ──────────────────────────────────────────────────────────────────

variable "grafana_admin_password" {
  description = <<-EOT
    Senha do usuario admin do Grafana.

    Nao ha valor default de proposito: uma senha em codigo seria a mesma em
    qualquer clone do repositorio. Informe via TF_VAR_grafana_admin_password
    (secret do pipeline), do mesmo jeito que database_password e
    token_signing_key no mechanical-hub-auth.
  EOT
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.grafana_admin_password) >= 12
    error_message = "A senha do admin do Grafana precisa ter ao menos 12 caracteres."
  }
}

# ── Dashboards ───────────────────────────────────────────────────────────────

variable "dashboard_files" {
  description = <<-EOT
    Arquivos JSON em dashboards/ publicados como ConfigMap para o sidecar do
    Grafana. Adicionar um dashboard = salvar o JSON exportado na pasta e
    incluir o nome do arquivo nesta lista.
  EOT
  type        = list(string)
  default = [
    "mechanical-hub-service-orders.json",
    "mechanical-hub-api.json",
  ]
}

# ── Limiares de alerta ───────────────────────────────────────────────────────

variable "alert_api_latency_seconds" {
  description = "Latencia p95 das APIs, em segundos, a partir da qual o alerta dispara."
  type        = number
  default     = 1.5
}

variable "alert_api_error_rate" {
  description = "Fracao de respostas 5xx (0 a 1) a partir da qual o alerta dispara."
  type        = number
  default     = 0.05

  validation {
    condition     = var.alert_api_error_rate > 0 && var.alert_api_error_rate < 1
    error_message = "alert_api_error_rate e uma fracao entre 0 e 1 (ex: 0.05 = 5%)."
  }
}
