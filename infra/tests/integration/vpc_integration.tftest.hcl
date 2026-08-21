# Testes de integracao do modulo VPC contra o LocalStack.
#
#   docker run --rm -d -p 4566:4566 localstack/localstack
#   terraform test -filter=tests/integration/vpc_integration.tftest.hcl
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
    ec2 = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

variables {
  project              = "mhub-test"
  environment          = "test"
  vpc_cidr             = "10.99.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs  = ["10.99.1.0/24", "10.99.2.0/24"]
  private_subnet_cidrs = ["10.99.11.0/24", "10.99.12.0/24"]
  tags                 = { ManagedBy = "terraform", Env = "test" }
}

run "vpc_is_created" {
  command = apply

  module {
    source = "../../modules/vpc"
  }

  assert {
    condition     = output.vpc_id != ""
    error_message = "A VPC nao foi criada — vpc_id vazio."
  }

  assert {
    condition     = output.vpc_cidr == var.vpc_cidr
    error_message = "A VPC criada nao usa o CIDR informado."
  }
}

run "two_public_subnets_created" {
  command = apply

  module {
    source = "../../modules/vpc"
  }

  assert {
    condition     = length(output.public_subnet_ids) == 2
    error_message = "Esperadas 2 subnets publicas, obtidas ${length(output.public_subnet_ids)}."
  }
}

run "two_private_subnets_created" {
  command = apply

  module {
    source = "../../modules/vpc"
  }

  assert {
    condition     = length(output.private_subnet_ids) == 2
    error_message = "Esperadas 2 subnets privadas, obtidas ${length(output.private_subnet_ids)}."
  }

  assert {
    condition     = tolist(output.private_subnet_cidrs) == var.private_subnet_cidrs
    error_message = "Os CIDRs privados exportados nao batem com os informados — o contrato quebrou."
  }
}
