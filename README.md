# mechanical-hub-infra

Infraestrutura base da plataforma Mechanical Hub: rede (VPC), cluster de
execução (EKS), registro de imagens (ECR) e a stack de observabilidade.

Este é o primeiro repositório a ser aplicado. Os demais leem os outputs daqui
via `terraform_remote_state`, conforme a ADR-0004.

## Escopo

| Dentro deste repositório | Fora |
| --- | --- |
| VPC, subnets, NAT, route tables | Banco de dados → `mechanical-hub-database` |
| Cluster EKS e node group | Autenticação serverless → `mechanical-hub-auth` |
| Repositório ECR | Aplicação e manifests → `mechanical-hub` |
| NLB interno da aplicação | Instrumentação do código → repositório de cada serviço |
| Stack de observabilidade (RFC-0004) | |

## Estrutura

```
infra/
├── providers.tf              backend "s3" vazio, configurado no pipeline
├── main.tf                   composição dos módulos
├── variables.tf
├── outputs.tf                contrato consumido pelos outros repositórios
├── terraform.tfvars.example
├── modules/
│   ├── vpc/  eks/  ecr/  app-lb/
│   └── observability/
│       ├── values/           values dos charts (templatefile)
│       └── dashboards/       JSON dos dashboards do Grafana
└── tests/
    ├── unit/                 mock_provider, rodam no CI
    └── integration/          LocalStack, rodam localmente
```

## Observabilidade

Implementa a RFC-0004 (`mechanical-hub/docs/architecture/rfc/0004-observabilidade-opentelemetry-prometheus-grafana.md`).
Quatro charts instalados no namespace `monitoring`, no mesmo padrão
`helm_release` já usado pelo `metrics-server`:

| Componente | Papel |
| --- | --- |
| `kube-prometheus-stack` | Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics |
| `loki` | Logs, modo SingleBinary sobre filesystem |
| `tempo` | Traces, chart monolítico sobre disco local |
| `opentelemetry-collector` | Porta de entrada única da telemetria (OTLP) |

### Decisões que não devem ser revertidas sem revisar a RFC

**Armazenamento local, não S3.** Loki e Tempo sobre object storage exigiriam
uma IAM role via IRSA — o mesmo guardrail do AWS Academy Lab que já derrubou o
AWS Load Balancer Controller. Nenhum recurso deste módulo cria IAM. Há um teste
unitário que quebra se alguém trocar o backend por S3.

**Dashboards e alertas são código.** Dashboards viram `ConfigMap` com a label
`grafana_dashboard: "1"`, que o sidecar do Grafana carrega sozinho; as regras
de alerta vão em `additionalPrometheusRulesMap`. Depois de um reset do
laboratório, `terraform apply` devolve tudo — o que se perde é o histórico
coletado, não a configuração.

> As regras **não** usam `kubernetes_manifest` para criar `PrometheusRule`:
> aquele recurso exige a CRD já instalada no momento do *plan*, o que quebraria
> o primeiro apply.

**Armazenamento efêmero por padrão.** `observability_persistence_enabled = false`
sobe sem depender de driver de volume. Reiniciar um pod zera o histórico daquele
sinal. Para trocar por volumes persistentes, ligue junto
`observability_manage_ebs_csi_addon` — a partir do Kubernetes 1.27 um PVC sem
driver CSI fica pendente para sempre.

### Adicionar um dashboard

1. Monte o painel na UI do Grafana (é mais rápido que escrever JSON à mão).
2. `Dashboard settings → JSON Model`, copie o conteúdo.
3. Salve em `infra/modules/observability/dashboards/<nome>.json`.
4. Acrescente o nome do arquivo em `var.dashboard_files`.

### Abrir o Grafana

Não há Ingress: expor uma interface administrativa na internet, a partir de um
cluster de laboratório com credenciais rotativas, não se justifica.

```bash
terraform -chdir=infra output -raw grafana_port_forward_command
# kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

Usuário `admin`, senha em `TF_VAR_grafana_admin_password`.

### Métricas esperadas da aplicação

Os dashboards e alertas já referenciam estas séries. Elas são o **contrato de
instrumentação** com os outros repositórios — até serem publicadas, os painéis
correspondentes ficam vazios e os alertas não disparam (não geram falso
positivo).

| Métrica | Origem | Tipo |
| --- | --- | --- |
| `http_server_requests_seconds_*` | `mechanical-hub` (Micrometer/Actuator) | histograma |
| `mechanical_hub_service_orders_created_total` | `mechanical-hub` | contador |
| `mechanical_hub_service_order_transitions_total{from,to,result}` | `mechanical-hub` | contador |
| `mechanical_hub_service_order_status_duration_seconds` | `mechanical-hub` | histograma, label `status` |
| `mechanical_hub_integration_errors_total{integration}` | `mechanical-hub` | contador |
| `mechanical_hub_auth_login_total{result}` | `mechanical-hub-auth` | contador |
| `mechanical_hub_auth_authorizer_total{decision}` | `mechanical-hub-auth` | contador |

As métricas `kube_*` e `container_*` usadas nos painéis de CPU/memória vêm do
kube-state-metrics e do kubelet — já disponíveis assim que a stack sobe.

### Limitação conhecida

As Lambdas do `mechanical-hub-auth` rodam na VPC, mas **fora** do Kubernetes:
não resolvem o DNS interno do cluster e por isso não alcançam os endpoints
`otlp_*`. A preparação existe (`observability_otlp_http_node_port` expõe o
coletor num NodePort), mas fechar esse caminho — um listener no NLB interno —
é trabalho da etapa em que as Lambdas forem instrumentadas.

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
| `app_nlb_arn`, `app_backend_base_url` | auth (VPC Link e integrações HTTP_PROXY) |
| `otlp_grpc_endpoint`, `otlp_http_endpoint` | `mechanical-hub` (`OTEL_EXPORTER_OTLP_ENDPOINT`) |

Os dois últimos são `null` quando `observability_enabled = false` — o consumidor
precisa tratar esse caso em vez de assumir que sempre existe um coletor.

## Uso local

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars

export TF_VAR_grafana_admin_password='...'   # mínimo 12 caracteres

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

# unitários — sem AWS, sem cluster
terraform test -filter=tests/unit/vpc_unit.tftest.hcl
terraform test -filter=tests/unit/observability_unit.tftest.hcl

# integração — exige LocalStack em localhost:4566
docker run --rm -d -p 4566:4566 localstack/localstack
terraform test -filter=tests/integration/vpc_integration.tftest.hcl
```

## Pipelines

- **CI** (`ci.yml`) — `fmt -check`, `validate` e testes unitários em todo PR e push para `main`.
- **Deploy** (`deploy.yml`) — `init` com backend S3, `validate`, `plan`, `apply` e publicação dos outputs do contrato no step summary.

Secrets esperados: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
`AWS_SESSION_TOKEN`, `AWS_ACCOUNT_ID`, `GRAFANA_ADMIN_PASSWORD`.

## Dimensionamento

A stack de observabilidade soma cerca de **0,6 vCPU e 1,8 GiB apenas em
requests**. Por isso `eks_node_desired_size` passou de 2 para 3 quando ela
entrou: com dois `t3.medium`, ela e a aplicação com HPA passam a disputar
espaço e aparecem pods em `Pending`. Voltar para 2 é uma linha — sabendo do
efeito.

## Ordem de aplicação

Dependência de **state** — quem precisa ler o output de quem para o `terraform apply` rodar:

```
mechanical-hub-infra → mechanical-hub-database → mechanical-hub-auth → mechanical-hub
```

Num ambiente criado do zero, a ordem de **execução dos pipelines** é outra: o smoke test de
login do `mechanical-hub-auth` roda logo após o `apply` dele e só responde 401 (em vez de 500)
depois que as migrations Flyway do `mechanical-hub` criaram `users.document_number` e o job da
role `mechanical_hub_auth` rodou no `mechanical-hub-database` — dependência de dado, não de
rede. A sequência que passa de primeira é:

```
mechanical-hub-infra → mechanical-hub-database → mechanical-hub (deploy) → job da role → mechanical-hub-auth
```

Uma exceção de ordem vale para a telemetria: o output `otlp_vpc_endpoint` deste repositório
precisa existir antes do `apply` do `mechanical-hub-auth`, senão as Lambdas sobem com a
telemetria desligada, sem erro (conferir o output `telemetry_enabled` no apply do `auth`).
Detalhes no adendo da ADR-0003, no `mechanical-hub`.
