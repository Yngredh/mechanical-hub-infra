# Valida a restricao de regiao do modulo raiz. Sem credenciais AWS: os
# provedores sao substituidos por mocks.
# Execute a partir de infra/: terraform test -filter=tests/unit/region_unit.tftest.hcl

mock_provider "aws" {}
mock_provider "helm" {}
mock_provider "kubernetes" {}

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
