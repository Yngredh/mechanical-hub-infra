# Testes unitarios do modulo app-lb (NLB interno, um target group por servico).
# Execute a partir de infra/:
#   terraform test -test-directory=tests/unit -filter=tests/unit/app_lb_unit.tftest.hcl

mock_provider "aws" {}

variables {
  project                   = "mechanical-hub"
  environment               = "production"
  vpc_id                    = "vpc-mock00001"
  private_subnet_ids        = ["subnet-mock0001", "subnet-mock0002"]
  private_subnet_cidrs      = ["10.0.11.0/24", "10.0.12.0/24"]
  cluster_security_group_id = "sg-cluster0001"
  autoscaling_group_name    = "eks-nodes-asg"
  tags                      = { ManagedBy = "terraform" }

  services = {
    orders       = { node_port = 30080, health_check_path = "/actuator/health/readiness" }
    stock        = { node_port = 30081, health_check_path = "/actuator/health/readiness" }
    billing      = { node_port = 30082, health_check_path = "/actuator/health/readiness" }
    orchestrator = { node_port = 30083, health_check_path = "/actuator/health/readiness" }
  }
}

run "um_target_group_e_listener_por_servico" {
  command = plan

  module {
    source = "./modules/app-lb"
  }

  assert {
    condition     = length(aws_lb_target_group.app) == 4 && length(aws_lb_listener.app) == 4 && length(aws_autoscaling_attachment.app) == 4
    error_message = "Esperado um target group, um listener e um attachment por servico."
  }

  # Contrato de portas: a NodePort do Service e a porta do listener sao a mesma.
  assert {
    condition = alltrue([for k, s in var.services :
      aws_lb_target_group.app[k].port == s.node_port && aws_lb_listener.app[k].port == s.node_port
    ])
    error_message = "Target group e listener precisam usar a node_port do servico."
  }

  assert {
    condition = alltrue([for k, s in var.services :
      aws_lb_target_group.app[k].health_check[0].path == s.health_check_path &&
      aws_lb_target_group.app[k].health_check[0].port == tostring(s.node_port)
    ])
    error_message = "O health check precisa bater na readiness do proprio servico."
  }

  # Nome de target group tem limite de 32 caracteres.
  assert {
    condition     = alltrue([for tg in aws_lb_target_group.app : length(tg.name) <= 32])
    error_message = "Nome de target group passou de 32 caracteres."
  }
}

run "uma_regra_de_sg_por_servico_no_cluster_sg" {
  command = plan

  module {
    source = "./modules/app-lb"
  }

  assert {
    condition     = length(aws_security_group_rule.app_nodeport_from_nlb) == 4
    error_message = "Esperada uma regra de entrada por servico."
  }

  # O SG adicional do modulo eks nao esta anexado aos nodes: uma regra nele
  # nao teria efeito e o health check do NLB falharia.
  assert {
    condition     = alltrue([for r in aws_security_group_rule.app_nodeport_from_nlb : r.security_group_id == var.cluster_security_group_id])
    error_message = "Todas as regras precisam ficar no cluster security group do EKS."
  }

  assert {
    condition = alltrue([for k, s in var.services :
      aws_security_group_rule.app_nodeport_from_nlb[k].from_port == s.node_port &&
      aws_security_group_rule.app_nodeport_from_nlb[k].to_port == s.node_port
    ])
    error_message = "Cada regra libera so a NodePort do seu servico."
  }
}

run "listener_otlp_continua_opcional" {
  command = plan

  module {
    source = "./modules/app-lb"
  }

  variables {
    otlp_node_port = 30318
  }

  assert {
    condition     = length(aws_lb_listener.otlp) == 1 && aws_lb_listener.otlp[0].port == 30318
    error_message = "Com otlp_node_port definido, o listener OTLP precisa existir."
  }

  assert {
    condition     = aws_security_group_rule.otlp_nodeport_from_nlb[0].security_group_id == var.cluster_security_group_id
    error_message = "A regra do OTLP tambem vai no cluster security group."
  }
}

run "nome_de_servico_longo_demais_e_rejeitado" {
  command = plan

  module {
    source = "./modules/app-lb"
  }

  variables {
    services = {
      orchestrator-com-nome-longo = { node_port = 30090, health_check_path = "/actuator/health/readiness" }
    }
  }

  expect_failures = [aws_lb_target_group.app]
}
