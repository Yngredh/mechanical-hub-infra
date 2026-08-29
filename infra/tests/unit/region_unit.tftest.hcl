# Valida a restricao de regiao do modulo raiz. Sem credenciais AWS: os
# provedores sao substituidos por mocks.
# Execute a partir de infra/: terraform test -filter=tests/unit/region_unit.tftest.hcl

mock_provider "aws" {}
mock_provider "helm" {}
mock_provider "kubernetes" {}

# A stack de observabilidade entra por padrao (var.observability_enabled) e
# exige senha do Grafana. Sem isto, todo run aqui falharia na validacao dessa
# variavel antes de chegar na regiao, que e o que estes testes medem.
variables {
  grafana_admin_password = "senha-de-teste-suficientemente-longa"
}

run "valid_region_us_east_1" {
  command = plan

  variables {
    aws_region           = "us-east-1"
    availability_zones   = ["us-east-1a", "us-east-1b"]
    public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
    private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
  }
}

run "valid_region_us_west_2" {
  command = plan

  variables {
    aws_region           = "us-west-2"
    availability_zones   = ["us-west-2a", "us-west-2b"]
    public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
    private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
  }
}

run "invalid_region_is_rejected" {
  command = plan

  variables {
    aws_region           = "eu-west-1"
    availability_zones   = ["eu-west-1a", "eu-west-1b"]
    public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
    private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
  }

  expect_failures = [var.aws_region]
}

# A stack de observabilidade precisa poder ser desligada sem editar codigo — e
# a valvula de escape quando o cluster do laboratorio esta sem folga. Desligada,
# nem a senha do Grafana e exigida.
run "observabilidade_pode_ser_desligada" {
  command = plan

  variables {
    aws_region             = "us-east-1"
    availability_zones     = ["us-east-1a", "us-east-1b"]
    public_subnet_cidrs    = ["10.0.1.0/24", "10.0.2.0/24"]
    private_subnet_cidrs   = ["10.0.11.0/24", "10.0.12.0/24"]
    observability_enabled  = false
    grafana_admin_password = ""
  }

  assert {
    condition     = length(module.observability) == 0
    error_message = "Com observability_enabled = false nenhum recurso da stack deve ser planejado."
  }
}
