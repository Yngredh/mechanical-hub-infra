# Testes unitarios do modulo ECR.
# Execute a partir de infra/:
#   terraform test -test-directory=tests/unit -filter=tests/unit/ecr_unit.tftest.hcl

mock_provider "aws" {
  mock_resource "aws_ecr_repository" {
    defaults = {
      repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/mechanical-hub/orders"
      registry_id    = "123456789012"
    }
  }
}

variables {
  project               = "mechanical-hub"
  services              = ["orders", "stock", "billing", "orchestrator"]
  image_retention_count = 10
  tags                  = { ManagedBy = "terraform" }
}

run "um_repositorio_por_servico" {
  command = plan

  module {
    source = "./modules/ecr"
  }

  assert {
    condition     = length(aws_ecr_repository.this) == 4
    error_message = "Esperado um repositorio ECR por servico (4)."
  }

  assert {
    condition = toset([for r in aws_ecr_repository.this : r.name]) == toset([
      "mechanical-hub/orders",
      "mechanical-hub/stock",
      "mechanical-hub/billing",
      "mechanical-hub/orchestrator",
    ])
    error_message = "Os repositorios precisam se chamar <project>/<servico>."
  }

  # O monolito da Fase 3 sai: os pipelines dos servicos nao publicam mais nele.
  assert {
    condition     = !contains([for r in aws_ecr_repository.this : r.name], "mechanical-hub/api")
    error_message = "O repositorio mechanical-hub/api nao deve mais existir."
  }
}

run "scan_on_push_em_todos" {
  command = plan

  module {
    source = "./modules/ecr"
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.this : r.image_scanning_configuration[0].scan_on_push])
    error_message = "scan_on_push precisa estar habilitado em todos os repositorios."
  }
}

run "lifecycle_policy_em_todos_com_a_retencao_informada" {
  command = plan

  module {
    source = "./modules/ecr"
  }

  variables {
    image_retention_count = 3
  }

  assert {
    condition     = length(aws_ecr_lifecycle_policy.this) == length(aws_ecr_repository.this)
    error_message = "Cada repositorio precisa da sua lifecycle policy."
  }

  assert {
    condition     = alltrue([for p in aws_ecr_lifecycle_policy.this : strcontains(p.policy, "\"countNumber\":3")])
    error_message = "A politica de lifecycle nao refletiu image_retention_count."
  }
}

run "servico_repetido_e_rejeitado" {
  command = plan

  module {
    source = "./modules/ecr"
  }

  variables {
    services = ["orders", "orders"]
  }

  expect_failures = [var.services]
}
