# Testes unitarios do modulo de observabilidade.
# Usa mock_provider — nao exige credenciais AWS, cluster nem Helm.
# Execute a partir de infra/: terraform test -filter=tests/unit/observability_unit.tftest.hcl

mock_provider "aws" {
  mock_resource "aws_eks_addon" {
    defaults = { id = "mechanical-hub-production-eks:aws-ebs-csi-driver" }
  }
}

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
}

run "stack_completa_e_planejada" {
  command = plan

  module {
    source = "../../modules/observability"
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
    source = "../../modules/observability"
  }

  assert {
    condition     = length(aws_eks_addon.ebs_csi_driver) == 0
    error_message = "Nenhum recurso AWS deve ser criado no caminho padrao — a stack sobe sem tocar em IAM."
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
    source = "../../modules/observability"
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
    source = "../../modules/observability"
  }

  assert {
    condition     = length(kubernetes_config_map.grafana_dashboards) == length(var.dashboard_files)
    error_message = "Cada arquivo em dashboard_files precisa virar um ConfigMap."
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

run "persistencia_ligada_provisiona_o_driver_de_volume" {
  command = plan

  module {
    source = "../../modules/observability"
  }

  variables {
    persistence_enabled  = true
    manage_ebs_csi_addon = true
  }

  assert {
    condition     = length(aws_eks_addon.ebs_csi_driver) == 1
    error_message = "Com a persistencia ligada, o addon do driver EBS precisa ser criado."
  }

  # Sem IRSA de proposito: o driver usa o instance profile dos nodes (LabRole),
  # porque o laboratorio nao deixa criar IAM role nova.
  assert {
    condition     = aws_eks_addon.ebs_csi_driver[0].service_account_role_arn == null
    error_message = "O addon nao deve pedir IRSA — o laboratorio nega criacao de IAM role."
  }

  assert {
    condition     = strcontains(helm_release.loki.values[0], "enabled: true")
    error_message = "Com persistence_enabled, o Loki precisa pedir volume persistente."
  }
}

run "senha_curta_do_grafana_e_rejeitada" {
  command = plan

  module {
    source = "../../modules/observability"
  }

  variables {
    grafana_admin_password = "123"
  }

  expect_failures = [var.grafana_admin_password]
}

run "node_port_fora_da_faixa_e_rejeitado" {
  command = plan

  module {
    source = "../../modules/observability"
  }

  variables {
    otlp_http_node_port = 8080
  }

  expect_failures = [var.otlp_http_node_port]
}
