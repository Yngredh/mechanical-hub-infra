# Testes unitarios do modulo ECR.
# Execute a partir de infra/: terraform test -filter=tests/unit/ecr_unit.tftest.hcl

mock_provider "aws" {
  mock_resource "aws_ecr_repository" {
    defaults = {
      id             = "mechanical-hub/api"
      repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/mechanical-hub/api"
      registry_id    = "123456789012"
    }
  }
  mock_resource "aws_ecr_lifecycle_policy" {
    defaults = { id = "mechanical-hub/api" }
  }
}

variables {
  project               = "mechanical-hub"
  image_retention_count = 10
  tags                  = { ManagedBy = "terraform" }
}

run "repository_name_follows_convention" {
  command = plan

  module {
    source = "../../modules/ecr"
  }

  assert {
    condition     = aws_ecr_repository.this.name == "${var.project}/api"
    error_message = "O repositorio precisa se chamar <project>/api."
  }
}

run "scan_on_push_is_enabled" {
  command = plan

  module {
    source = "../../modules/ecr"
  }

  assert {
    condition     = aws_ecr_repository.this.image_scanning_configuration[0].scan_on_push
    error_message = "scan_on_push precisa estar habilitado no repositorio ECR."
  }
}

run "lifecycle_policy_uses_retention_count" {
  command = plan

  module {
    source = "../../modules/ecr"
  }

  variables {
    image_retention_count = 3
  }

  assert {
    condition     = strcontains(aws_ecr_lifecycle_policy.this.policy, "\"countNumber\":3")
    error_message = "A politica de lifecycle nao refletiu image_retention_count."
  }
}
