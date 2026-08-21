# Testes unitarios do modulo VPC.
# Usa mock_provider — nao exige credenciais AWS nem LocalStack.
# Execute a partir de infra/: terraform test -filter=tests/unit/vpc_unit.tftest.hcl

mock_provider "aws" {
  mock_resource "aws_vpc" {
    defaults = { id = "vpc-mock00001" }
  }
  mock_resource "aws_internet_gateway" {
    defaults = { id = "igw-mock00001" }
  }
  mock_resource "aws_subnet" {
    defaults = { id = "subnet-mock0001" }
  }
  mock_resource "aws_eip" {
    defaults = { id = "eipalloc-mock001", allocation_id = "eipalloc-mock001" }
  }
  mock_resource "aws_nat_gateway" {
    defaults = { id = "nat-mock000001" }
  }
  mock_resource "aws_route_table" {
    defaults = { id = "rtb-mock000001" }
  }
  mock_resource "aws_route_table_association" {
    defaults = { id = "rtbassoc-mock01" }
  }
}

variables {
  project              = "test"
  environment          = "test"
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
  tags                 = { ManagedBy = "terraform" }
}

run "vpc_plan_is_valid" {
  command = plan

  module {
    source = "../../modules/vpc"
  }

  assert {
    condition     = aws_vpc.this.cidr_block == var.vpc_cidr
    error_message = "A VPC planejada nao usa o CIDR informado em vpc_cidr."
  }

  assert {
    condition     = aws_vpc.this.enable_dns_hostnames
    error_message = "enable_dns_hostnames precisa estar ligado — o EKS depende de DNS interno."
  }
}

run "one_subnet_per_az_is_planned" {
  command = plan

  module {
    source = "../../modules/vpc"
  }

  assert {
    condition     = length(aws_subnet.public) == length(var.availability_zones)
    error_message = "Esperada uma subnet publica por AZ."
  }

  assert {
    condition     = length(aws_subnet.private) == length(var.availability_zones)
    error_message = "Esperada uma subnet privada por AZ."
  }
}

run "private_subnets_are_not_public" {
  command = plan

  module {
    source = "../../modules/vpc"
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private : s.map_public_ip_on_launch == false])
    error_message = "Subnet privada nao pode atribuir IP publico automaticamente."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch])
    error_message = "Subnet publica precisa atribuir IP publico automaticamente."
  }
}

run "cidr_az_mismatch_is_caught" {
  command = plan

  module {
    source = "../../modules/vpc"
  }

  # Tres CIDRs para duas AZs: sem a precondicao, o modulo criaria duas subnets
  # na mesma AZ silenciosamente.
  variables {
    public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  }

  expect_failures = [terraform_data.subnet_precondition]
}
