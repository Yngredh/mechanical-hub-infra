# Testes unitarios do modulo de observabilidade.
# Usa mock_provider — nao exige credenciais AWS, cluster nem Helm.
# Execute a partir de infra/:
#   terraform test -test-directory=tests/unit -filter=tests/unit/observability_unit.tftest.hcl

mock_provider "helm" {
  mock_resource "helm_release" {
    defaults = { id = "mock-release" }
  }
}

mock_provider "kubernetes" {
  mock_resource "kubernetes_namespace" {
    defaults = { id = "monitoring" }
  }
  mock_resource "kubernetes_config_map" {
    defaults = { id = "monitoring/mock-config-map" }
  }
}

variables {
  project                = "mechanical-hub"
  environment            = "production"
  cluster_name           = "mechanical-hub-production-eks"
  grafana_admin_password = "senha-de-teste-suficientemente-longa"
  tags                   = { ManagedBy = "terraform" }

  services = {
    orders       = { queue = "mechanical-hub-orders-commands.fifo", dlq = "mechanical-hub-orders-commands-dlq.fifo" }
    stock        = { queue = "mechanical-hub-stock-commands.fifo", dlq = "mechanical-hub-stock-commands-dlq.fifo" }
    billing      = { queue = "mechanical-hub-billing-commands.fifo", dlq = "mechanical-hub-billing-commands-dlq.fifo" }
    orchestrator = { queue = "mechanical-hub-orchestrator-events.fifo", dlq = "mechanical-hub-orchestrator-events-dlq.fifo" }
  }
  queue_names = ["mechanical-hub-orders-commands.fifo", "mechanical-hub-orchestrator-events.fifo"]
  dlq_names   = ["mechanical-hub-orders-commands-dlq.fifo", "mechanical-hub-orchestrator-events-dlq.fifo"]
}

run "stack_completa_e_planejada" {
  command = plan

  module {
    source = "./modules/observability"
  }

  assert {
    condition     = kubernetes_namespace.observability.metadata[0].name == "monitoring"
    error_message = "A stack precisa ser instalada no namespace informado em var.namespace."
  }

  assert {
    condition = alltrue([
      helm_release.kube_prometheus_stack.namespace == "monitoring",
      helm_release.loki.namespace == "monitoring",
      helm_release.tempo.namespace == "monitoring",
      helm_release.otel_collector.namespace == "monitoring",
      helm_release.otel_logs_agent.namespace == "monitoring",
    ])
    error_message = "Os cinco releases precisam ficar no mesmo namespace."
  }

  # Sao dois coletores por necessidade, nao por redundancia: o gateway recebe
  # OTLP (metricas e traces), e o agente le o arquivo de log de cada node — o
  # que so um DaemonSet consegue fazer. Se o agente virar Deployment, os logs
  # de todos os nodes menos um deixam de chegar ao Loki, em silencio.
  assert {
    condition     = strcontains(helm_release.otel_logs_agent.values[0], "mode: daemonset")
    error_message = "O coletor de logs precisa rodar como DaemonSet para ler /var/log/pods de cada node."
  }

  assert {
    condition     = strcontains(helm_release.otel_collector.values[0], "mode: deployment")
    error_message = "O coletor que recebe OTLP e um gateway unico, nao um agente por node."
  }
}

# A RFC-0004 rejeita object storage justamente porque exigiria IRSA — o mesmo
# guardrail de IAM que ja derrubou o AWS Load Balancer Controller. Este teste
# existe para que uma mudanca futura para S3 quebre em vez de passar em
# silencio e so falhar no laboratorio.
run "sem_dependencia_de_iam_no_caminho_padrao" {
  command = plan

  module {
    source = "./modules/observability"
  }

  # O CloudWatch entra pela cadeia padrao do SDK (LabRole dos nodes via IMDS),
  # nunca por chave de acesso — as do Lab expiram a cada sessao.
  assert {
    condition     = strcontains(helm_release.kube_prometheus_stack.values[0], "authType: default")
    error_message = "A fonte CloudWatch precisa usar as credenciais da role dos nodes (authType: default)."
  }

  assert {
    condition     = strcontains(helm_release.loki.values[0], "type: filesystem")
    error_message = "O Loki precisa usar armazenamento filesystem: S3 exigiria IRSA (RFC-0004)."
  }

  assert {
    condition     = strcontains(helm_release.tempo.values[0], "backend: local")
    error_message = "O Tempo precisa usar backend local: S3 exigiria IRSA (RFC-0004)."
  }
}

run "retencao_de_metricas_cobre_mais_de_um_dia" {
  command = plan

  module {
    source = "./modules/observability"
  }

  # O painel de volume diario de OS exigido pela Fase 3 nao mostra tendencia
  # com um unico dia de historico — foi o que descartou o tier gratuito do
  # Datadog na RFC-0004. Retencao curta demais aqui repetiria o mesmo problema.
  assert {
    condition     = strcontains(helm_release.kube_prometheus_stack.values[0], "retention: 7d")
    error_message = "A retencao configurada nao chegou aos values do Prometheus."
  }

  assert {
    condition     = strcontains(helm_release.kube_prometheus_stack.values[0], "enableRemoteWriteReceiver: true")
    error_message = "Sem o receptor de remote write, nada do que o coletor exporta chega ao Prometheus."
  }
}

run "dashboards_viram_configmap_com_a_label_do_sidecar" {
  command = plan

  module {
    source = "./modules/observability"
  }

  assert {
    condition     = length(kubernetes_config_map.grafana_dashboards) == length(var.dashboard_files) + length(var.services)
    error_message = "Cada arquivo em dashboard_files e cada servico precisam virar um ConfigMap."
  }

  assert {
    condition = alltrue([for s in keys(var.services) :
      contains(keys(kubernetes_config_map.grafana_dashboards), "mechanical-hub-service-${s}.json")
    ])
    error_message = "Cada servico precisa do seu painel."
  }

  # Marcador esquecido = painel com consulta para uma fila chamada
  # "__QUEUE__", vazio e sem erro.
  assert {
    condition = alltrue([for cm in kubernetes_config_map.grafana_dashboards :
      alltrue([for v in values(cm.data) : !strcontains(v, "__SERVICE__") && !strcontains(v, "__QUEUE") && !strcontains(v, "__DLQ")])
    ])
    error_message = "Sobrou marcador (__SERVICE__, __QUEUE__, __DLQ__) sem substituir em algum painel."
  }

  assert {
    condition     = strcontains(kubernetes_config_map.grafana_dashboards["mechanical-hub-service-orchestrator.json"].data["mechanical-hub-service-orchestrator.json"], "mechanical-hub-orchestrator-events-dlq.fifo")
    error_message = "O painel do orchestrator precisa mostrar a DLQ da fila que ele consome."
  }

  # Sem esta label o sidecar do Grafana ignora o ConfigMap e o dashboard nunca
  # aparece — falha silenciosa, o pior tipo.
  assert {
    condition = alltrue([
      for cm in kubernetes_config_map.grafana_dashboards :
      lookup(cm.metadata[0].labels, "grafana_dashboard", "") == "1"
    ])
    error_message = "Todo ConfigMap de dashboard precisa da label grafana_dashboard=1."
  }
}

# O driver EBS CSI mora no modulo eks desde a Fase 4; aqui so se confere que a
# persistencia usa a StorageClass recebida.
run "persistencia_ligada_usa_a_storage_class_gp3" {
  command = plan

  module {
    source = "./modules/observability"
  }

  variables {
    persistence_enabled = true
  }

  assert {
    condition     = strcontains(helm_release.loki.values[0], "enabled: true")
    error_message = "Com persistence_enabled, o Loki precisa pedir volume persistente."
  }

  assert {
    condition     = strcontains(helm_release.kube_prometheus_stack.values[0], "storageClassName: gp3")
    error_message = "O volume do Prometheus precisa usar a StorageClass gp3."
  }
}

run "scrape_e_alertas_dos_servicos" {
  command = plan

  module {
    source = "./modules/observability"
  }

  assert {
    condition = alltrue([
      strcontains(helm_release.kube_prometheus_stack.values[0], "metrics_path: /actuator/prometheus"),
      strcontains(helm_release.kube_prometheus_stack.values[0], "regex: \"billing|orchestrator|orders|stock\""),
      strcontains(helm_release.kube_prometheus_stack.values[0], "names: [\"production\"]"),
    ])
    error_message = "O scrape precisa cobrir /actuator/prometheus dos 4 servicos no namespace da aplicacao."
  }

  assert {
    condition     = strcontains(helm_release.kube_prometheus_stack.values[0], "outbox_oldest_pending_age_seconds{namespace=\"production\"}) > 60")
    error_message = "O alerta do outbox precisa disparar acima de 60 s (failure_handling.md §4)."
  }
}

run "senha_curta_do_grafana_e_rejeitada" {
  command = plan

  module {
    source = "./modules/observability"
  }

  variables {
    grafana_admin_password = "123"
  }

  expect_failures = [var.grafana_admin_password]
}

run "node_port_fora_da_faixa_e_rejeitado" {
  command = plan

  module {
    source = "./modules/observability"
  }

  variables {
    otlp_http_node_port = 8080
  }

  expect_failures = [var.otlp_http_node_port]
}
