# Testes do modulo raiz: limites do AWS Academy Lab e contrato de outputs da
# Fase 4 (spec, secao 3). Sem credenciais AWS: os provedores sao mocks.
# Execute a partir de infra/:
#   terraform test -test-directory=tests/unit -filter=tests/unit/root_unit.tftest.hcl

mock_provider "aws" {
  mock_data "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/LabRole" }
  }
}
mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  grafana_admin_password = "senha-de-teste-suficientemente-longa"
}

# ── Limites do Lab: 9 instancias e 32 vCPU na conta ──────────────────────────

run "cluster_padrao_cabe_no_lab" {
  command = plan

  assert {
    condition     = var.eks_node_instance_type == "t3.large" && var.eks_node_desired_size == 3
    error_message = "A Fase 4 usa 3 x t3.large."
  }

  # t3.large = 2 vCPU. O pior caso e o node group no maximo.
  assert {
    condition     = var.eks_node_max_size <= 9 && var.eks_node_max_size * 2 <= 32
    error_message = "O maximo do node group passa do limite do Lab."
  }
}

run "tipo_de_instancia_maior_e_rejeitado" {
  command = plan

  variables {
    eks_node_instance_type = "m5.2xlarge"
  }

  expect_failures = [var.eks_node_instance_type]
}

run "node_group_acima_do_limite_e_rejeitado" {
  command = plan

  variables {
    eks_node_max_size = 10
  }

  expect_failures = [var.eks_node_max_size]
}

# ── Contrato de outputs ──────────────────────────────────────────────────────

run "outputs_por_servico_e_por_fila" {
  command = plan

  assert {
    condition     = toset(keys(output.ecr_repository_urls)) == toset(["orders", "stock", "billing", "orchestrator"])
    error_message = "ecr_repository_urls precisa ter uma chave por servico."
  }

  assert {
    condition     = toset(keys(output.app_backend_base_urls)) == toset(["orders", "stock", "billing", "orchestrator"])
    error_message = "app_backend_base_urls precisa ter uma chave por servico."
  }

  assert {
    condition = alltrue([for o in [output.sqs_queue_urls, output.sqs_queue_arns, output.sqs_dlq_urls] :
      toset(keys(o)) == toset(["orders-commands", "stock-commands", "billing-commands", "orchestrator-events"])
    ])
    error_message = "Os outputs sqs_* precisam usar as chaves de fila da spec."
  }
}

run "node_port_repetida_e_rejeitada" {
  command = plan

  variables {
    services = {
      orders = { node_port = 30080 }
      stock  = { node_port = 30080 }
    }
  }

  expect_failures = [var.services]
}
