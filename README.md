# mechanical-hub-infra

Infraestrutura base da plataforma Mechanical Hub: rede (VPC), cluster de
execução (EKS) e registro de imagens (ECR).

Este é o primeiro repositório a ser aplicado. Os demais leem os outputs daqui
via `terraform_remote_state`, conforme a ADR-0004.

## Escopo

| Dentro deste repositório | Fora |
| --- | --- |
| VPC, subnets, NAT, route tables | Banco de dados → `mechanical-hub-database` |
| Cluster EKS e node group | Autenticação serverless → `mechanical-hub-auth` |
| Repositório ECR | Aplicação e manifests → `mechanical-hub` |

## Estrutura

```
infra/
├── providers.tf              backend "s3" vazio, configurado no pipeline
├── main.tf                   composição dos módulos
├── variables.tf
├── outputs.tf                contrato consumido pelos outros repositórios
├── terraform.tfvars.example
├── modules/{vpc,eks,ecr}/
└── tests/
    ├── unit/                 mock_provider, rodam no CI
    └── integration/          LocalStack, rodam localmente
```

## Contrato de outputs

Alterar ou remover qualquer um destes é uma mudança quebra-compatibilidade e
exige coordenação com os consumidores.

| Output | Consumidor |
| --- | --- |
| `vpc_id` | database, auth |
| `vpc_cidr` | database (fallback de liberação) |
| `private_subnet_ids` | database, auth |
| `private_subnet_cidrs` | database (regras de entrada do RDS) |
| `public_subnet_ids` | load balancers do cluster |
| `eks_cluster_name` | pipeline de deploy de `mechanical-hub` |
| `eks_cluster_endpoint` | pipeline de deploy de `mechanical-hub` |
| `eks_cluster_security_group_id` | database (`allowed_security_group_ids`) |
| `ecr_repository_url` | pipeline de build de `mechanical-hub` |

## Uso local

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars

terraform init \
  -backend-config="bucket=mechanical-hub-tfstate-<conta>" \
  -backend-config="key=mechanical-hub-infra/terraform.tfstate" \
  -backend-config="region=us-east-1"

terraform plan
terraform apply
```

## Testes

```bash
cd infra
terraform init -backend=false

# unitários — sem AWS
terraform test -filter=tests/unit/vpc_unit.tftest.hcl

# integração — exige LocalStack em localhost:4566
docker run --rm -d -p 4566:4566 localstack/localstack
terraform test -filter=tests/integration/vpc_integration.tftest.hcl
```

## Pipelines

- **CI** (`ci.yml`) — `fmt -check`, `validate` e testes unitários em todo PR e push para `main`.
- **Deploy** (`deploy.yml`) — `init` com backend S3, `validate`, `plan`, `apply` e publicação dos outputs do contrato no step summary.

Secrets esperados: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
`AWS_SESSION_TOKEN`, `AWS_ACCOUNT_ID`.

## Ordem de aplicação

```
mechanical-hub-infra → mechanical-hub-database → mechanical-hub-auth → mechanical-hub
```
