# =============================================================================
# NLB interno da aplicacao — alvo do VPC Link do mechanical-hub-auth
#
# Conectividade privada (adendo da ADR-0003): o Service da aplicacao deixa de ser
# type: LoadBalancer publico (qualquer um que descobrisse o DNS do ELB podia
# forjar os cabecalhos x-user-* que o GatewayAuthenticationFilter confia sem
# validar assinatura). O API Gateway passa a alcancar a aplicacao por
# conectividade privada.
#
# Por que Terraform provisiona o NLB, e nao um controller do Kubernetes:
#   - O AWS Load Balancer Controller (o caminho moderno) exige IRSA — uma IAM
#     role nova vinculada a um provedor OIDC do cluster. O AWS Academy Lab nega
#     explicitamente escrita em iam:* (guardrail confirmado: ate iam:GetPolicy,
#     uma leitura, retorna AccessDenied). Criar essa role nao e possivel.
#   - O provisionador in-tree (anotacao aws-load-balancer-type: nlb) usa a
#     LabRole que o cluster ja tem, sem pedir IAM novo, mas depende de codigo
#     que a AWS vem descontinuando — nao e garantido continuar funcionando em
#     versoes futuras do EKS.
#   - Provisionando aqui, a criacao roda sob a mesma identidade (voclabs, via
#     as credenciais do pipeline) que ja aplica VPC/EKS/ECR com sucesso hoje —
#     zero permissao nova, zero dependencia de um controller adicional.
#
# Cada servico (Fase 4, ADR-0005) tem um Service type: NodePort numa porta
# fixa (var.services). Para cada um ha um target group nessa porta, anexado a
# Auto Scaling Group dos nodes, e um listener na mesma porta do NLB: o
# kube-proxy distribui a partir dai para os pods, sem o NLB precisar saber
# onde cada pod esta. Um NLB so para todos — o mechanical-hub-auth continua
# com um unico VPC Link e escolhe o servico pela porta.
# =============================================================================

locals {
  name_prefix = "${var.project}-${var.environment}"

  # Nome de target group tem no maximo 32 caracteres, e
  # "mechanical-hub-production-orchestrator" tem 38. O ambiente entra
  # abreviado (prod, stag) so aqui; o resto dos recursos usa o nome inteiro.
  tg_prefix = "${var.project}-${substr(var.environment, 0, 4)}"
}

resource "aws_lb" "app" {
  name               = "${local.name_prefix}-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.private_subnet_ids

  tags = merge(var.tags, { Name = "${local.name_prefix}-nlb" })
}

resource "aws_lb_target_group" "app" {
  for_each = var.services

  name        = "${local.tg_prefix}-${each.key}"
  port        = each.value.node_port
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  # Desliga a preservacao do IP original do cliente. Sem isso, o pacote chega
  # ao node com o IP de quem chamou o NLB (o ENI do VPC Link, dentro da VPC),
  # e a regra de seguranca abaixo precisaria conhecer a subnet especifica do
  # VPC Link. Desligado, o trafego chega ao node com o IP privado do proprio
  # NLB, e liberar o CIDR das subnets privadas basta — mesmo padrao de
  # liberacao por CIDR ja usado no RDS (mechanical-hub-database), em vez de
  # depender de referencia a outro security group.
  preserve_client_ip = "false"

  health_check {
    protocol            = "HTTP"
    path                = each.value.health_check_path
    port                = tostring(each.value.node_port)
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }

  tags = merge(var.tags, { Name = "${local.tg_prefix}-${each.key}", Service = each.key })

  lifecycle {
    # O listener aponta para o target group: sem isto, uma substituicao tenta
    # apagar o target group ainda em uso e falha com ResourceInUse.
    create_before_destroy = true

    precondition {
      condition     = length("${local.tg_prefix}-${each.key}") <= 32
      error_message = "Nome do target group passa de 32 caracteres; encurte o nome do servico."
    }
  }
}

# Anexa cada target group a ASG do node group inteiro: escala/substitui nodes
# sem reconciliacao manual, o proprio ASG mantem os membros em dia.
resource "aws_autoscaling_attachment" "app" {
  for_each = var.services

  autoscaling_group_name = var.autoscaling_group_name
  lb_target_group_arn    = aws_lb_target_group.app[each.key].arn
}

resource "aws_lb_listener" "app" {
  for_each = var.services

  load_balancer_arn = aws_lb.app.arn
  port              = each.value.node_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[each.key].arn
  }
}

# Libera a NodePort de cada servico a partir das subnets privadas — de la vem
# o trafego do NLB, com preserve_client_ip desligado acima. A regra vai no
# cluster security group gerenciado pelo EKS, que e o anexado aos nodes; o SG
# adicional do modulo eks nao esta nos nodes e uma regra nele nao teria efeito.
resource "aws_security_group_rule" "app_nodeport_from_nlb" {
  for_each = var.services

  security_group_id = var.cluster_security_group_id
  type              = "ingress"
  from_port         = each.value.node_port
  to_port           = each.value.node_port
  protocol          = "tcp"
  cidr_blocks       = var.private_subnet_cidrs
  description       = "NodePort do servico ${each.key}, alcancado pelo NLB interno (VPC Link do mechanical-hub-auth)"
}

# Na Fase 3 havia um unico servico (o monolito) na porta 30080, que agora e a
# do orders. Mover os enderecos evita que o listener novo da 30080 seja criado
# antes de o antigo ser apagado (DuplicateListener) e que a regra de SG
# identica colida com a anterior.
moved {
  from = aws_lb_target_group.app
  to   = aws_lb_target_group.app["orders"]
}

moved {
  from = aws_autoscaling_attachment.app
  to   = aws_autoscaling_attachment.app["orders"]
}

moved {
  from = aws_lb_listener.app
  to   = aws_lb_listener.app["orders"]
}

moved {
  from = aws_security_group_rule.app_nodeport_from_nlb
  to   = aws_security_group_rule.app_nodeport_from_nlb["orders"]
}

# =============================================================================
# Caminho de telemetria das Lambdas (RFC-0004, etapa 3)
#
# As funcoes do mechanical-hub-auth rodam na VPC, mas fora do Kubernetes: elas
# nao resolvem o DNS interno do cluster e nao alcancam o Service ClusterIP do
# coletor OpenTelemetry. Sem uma ponte, a telemetria delas simplesmente nao tem
# para onde ir.
#
# A ponte reaproveita o mesmo NLB interno que ja atende a aplicacao: mais um
# listener, apontando para o NodePort em que o coletor foi exposto. Zero
# recurso de rede novo, zero IAM, e o mesmo padrao das portas dos servicos.
#
# Tudo aqui e opcional (count): com var.otlp_node_port nulo, nada e criado e o
# modulo continua se comportando exatamente como antes.
# =============================================================================

resource "aws_lb_target_group" "otlp" {
  count = var.otlp_node_port == null ? 0 : 1

  name        = "${local.name_prefix}-otlp"
  port        = var.otlp_node_port
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  preserve_client_ip = "false"

  # Health check TCP, e nao HTTP: o coletor expoe o endpoint de saude numa
  # porta diferente da de ingestao, que nao esta publicada como NodePort. Como
  # o kube-proxy aceita a conexao em qualquer node enquanto o Service existir,
  # a checagem TCP responde a pergunta que importa aqui — o caminho ate o
  # coletor esta de pe.
  health_check {
    protocol            = "TCP"
    port                = tostring(var.otlp_node_port)
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}-otlp-tg" })
}

resource "aws_autoscaling_attachment" "otlp" {
  count = var.otlp_node_port == null ? 0 : 1

  autoscaling_group_name = var.autoscaling_group_name
  lb_target_group_arn    = aws_lb_target_group.otlp[0].arn
}

resource "aws_lb_listener" "otlp" {
  count = var.otlp_node_port == null ? 0 : 1

  load_balancer_arn = aws_lb.app.arn
  port              = var.otlp_node_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.otlp[0].arn
  }
}

resource "aws_security_group_rule" "otlp_nodeport_from_nlb" {
  count = var.otlp_node_port == null ? 0 : 1

  security_group_id = var.cluster_security_group_id
  type              = "ingress"
  from_port         = var.otlp_node_port
  to_port           = var.otlp_node_port
  protocol          = "tcp"
  cidr_blocks       = var.private_subnet_cidrs
  description       = "NodePort OTLP/HTTP do coletor, alcancado pelas Lambdas via NLB interno"
}
