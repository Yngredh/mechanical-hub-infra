# Testes de integracao do modulo ECR contra o LocalStack.
#
#   docker run --rm -d -p 4566:4566 localstack/localstack
#   terraform test -filter=tests/integration/ecr_integration.tftest.hcl
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
  image_retention_count = 5
  tags                  = { ManagedBy = "terraform", Env = "test" }
}

run "ecr_repository_is_created" {
  command = apply

  module {
    source = "../../modules/ecr"
  }

  assert {
    condition     = output.repository_url != ""
    error_message = "O repositorio ECR nao foi criado — repository_url vazio."
  }

  assert {
    condition     = endswith(output.repository_url, "mechanical-hub/api")
    error_message = "A URL do repositorio ECR nao termina em 'mechanical-hub/api'."
  }

  assert {
    condition     = output.repository_name == "mechanical-hub/api"
    error_message = "O nome exportado do repositorio ECR quebrou o contrato."
  }
}
