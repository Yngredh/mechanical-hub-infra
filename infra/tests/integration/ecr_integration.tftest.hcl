# Testes de integracao do modulo ECR contra o LocalStack.
#
#   docker run --rm -d -p 4566:4566 localstack/localstack
#   terraform init -test-directory=tests/integration
#   terraform test -test-directory=tests/integration -filter=tests/integration/ecr_integration.tftest.hcl
#
# Nao rodam no CI: dependem de um LocalStack acessivel em localhost:4566.

provider "aws" {
  access_key = "test"
  secret_key = "test"
  region     = "us-east-1"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ecr = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

variables {
  project               = "mechanical-hub"
  services              = ["orders", "stock", "billing", "orchestrator"]
  image_retention_count = 5
  tags                  = { ManagedBy = "terraform", Env = "test" }
}

run "um_repositorio_por_servico_e_criado" {
  command = apply

  module {
    source = "./modules/ecr"
  }

  assert {
    condition     = length(output.repository_urls) == 4
    error_message = "Esperados 4 repositorios ECR criados."
  }

  assert {
    condition     = alltrue([for s, url in output.repository_urls : endswith(url, "mechanical-hub/${s}")])
    error_message = "A URL de cada repositorio precisa terminar em mechanical-hub/<servico>."
  }

  assert {
    condition     = output.repository_names["orchestrator"] == "mechanical-hub/orchestrator"
    error_message = "O nome exportado do repositorio quebrou o contrato."
  }

  assert {
    condition     = output.registry_id != ""
    error_message = "registry_id vazio."
  }
}
