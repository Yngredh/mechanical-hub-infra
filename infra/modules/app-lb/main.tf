# =============================================================================
# NLB interno da aplicacao — alvo do VPC Link do mechanical-hub-auth
#
# Fecha o item 47 do plano: o Service da aplicacao deixa de ser
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
# O Service da aplicacao (mechanical-hub) vira type: NodePort na porta fixa
# var.node_port. O target group aponta para essa porta, anexado a Auto Scaling
# Group dos nodes: o kube-proxy distribui a partir dai para os pods, sem o NLB
# precisar saber onde cada pod esta.
# =============================================================================

locals {
  name_prefix = "${var.project}-${var.environment}"
}

resource "aws_lb" "app" {
  name               = "${local.name_prefix}-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.private_subnet_ids

  tags = merge(var.tags, { Name = "${local.name_prefix}-nlb" })
}

resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-tg"
  port        = var.node_port
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
    path                = var.health_check_path
    port                = tostring(var.node_port)
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}-tg" })
}

# Anexa o target group a ASG do node group inteiro: escala/substitui nodes sem
# reconciliacao manual, o proprio ASG mantem os membros do target group em dia.
resource "aws_autoscaling_attachment" "app" {
  autoscaling_group_name = var.autoscaling_group_name
  lb_target_group_arn    = aws_lb_target_group.app.arn
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = var.node_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Libera o NodePort da aplicacao a partir das subnets privadas — de la vem o
# trafego do NLB, com preserve_client_ip desligado acima.
resource "aws_security_group_rule" "app_nodeport_from_nlb" {
  security_group_id = var.node_security_group_id
  type              = "ingress"
  from_port         = var.node_port
  to_port           = var.node_port
  protocol          = "tcp"
  cidr_blocks       = var.private_subnet_cidrs
  description       = "NodePort da aplicacao, alcancado pelo NLB interno (VPC Link do mechanical-hub-auth)"
}
