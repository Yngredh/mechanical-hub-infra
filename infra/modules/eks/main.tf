locals {
  cluster_name = "${var.project}-${var.environment}-eks"
}

# ── Security Group: Cluster control plane ─────────────────────────────────────

resource "aws_security_group" "cluster" {
  name        = "${local.cluster_name}-cluster-sg"
  description = "EKS cluster control plane security group"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(var.tags, { Name = "${local.cluster_name}-cluster-sg" })
}

# ── Security Group: Worker nodes ──────────────────────────────────────────────

resource "aws_security_group" "nodes" {
  name        = "${local.cluster_name}-nodes-sg"
  description = "EKS worker nodes security group"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Allow node-to-node communication"
  }

  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id]
    description     = "Allow control plane to reach nodes"
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id]
    description     = "Allow control plane HTTPS to nodes"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound (needed to reach ECR, S3, etc.)"
  }

  tags = merge(var.tags, { Name = "${local.cluster_name}-nodes-sg" })
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  role_arn = var.lab_role_arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  tags = merge(var.tags, { Name = local.cluster_name })
}

# ── Launch template dos nodes ─────────────────────────────────────────────────
#
# Existe so para fixar os metadados da instancia. Os pods leem as credenciais
# da LabRole pelo IMDS (SQS e driver EBS CSI, sem IRSA — bloqueado no Lab), e
# a resposta do IMDSv2 a um pod atravessa um salto de rede a mais: com
# hop limit 1 ela morre no caminho e o SDK falha sem credencial. O padrao do
# node group gerenciado ja usa 2, mas depender de padrao implicito aqui e
# arriscar um erro de credencial dificil de diagnosticar; fica explicito.
#
# Sem image_id e sem instance_type de proposito: a AMI continua sendo a
# otimizada que o EKS escolhe, e o tipo de instancia fica no node group.

resource "aws_launch_template" "nodes" {
  name_prefix = "${local.cluster_name}-nodes-"
  description = "Metadados de instancia dos nodes do EKS (IMDSv2, hop limit para pods)"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = var.node_metadata_hop_limit
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${local.cluster_name}-node" })
  }

  tags = var.tags
}

# ── EKS Managed Node Group ────────────────────────────────────────────────────

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.cluster_name}-nodes"
  node_role_arn   = var.lab_role_arn
  subnet_ids      = var.private_subnet_ids

  instance_types = [var.node_instance_type]

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge(var.tags, { Name = "${local.cluster_name}-nodes" })
}

# ── metrics-server ────────────────────────────────────────────────────────────

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.0"

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }

  depends_on = [aws_eks_node_group.this]
}

# ── Driver EBS CSI ────────────────────────────────────────────────────────────
#
# A partir do Kubernetes 1.27 o provisionador EBS in-tree deixou de existir:
# sem o driver CSI, todo PersistentVolumeClaim fica pendente para sempre. Na
# Fase 4 o MongoDB (mechanical-hub-database) precisa de volume, por isso o
# driver saiu do modulo de observabilidade, onde era opcional e desligado, e
# virou parte do cluster.
#
# Criado SEM service_account_role_arn de proposito: o driver usa as
# credenciais do instance profile dos nodes (a LabRole) pelo IMDS, em vez de
# uma IAM role via IRSA, que o Lab nao deixa criar. Se falhar por permissao,
# var.ebs_csi_enabled = false desliga o driver e o MongoDB fica com
# armazenamento efemero.

resource "aws_eks_addon" "ebs_csi_driver" {
  count = var.ebs_csi_enabled ? 1 : 0

  cluster_name = aws_eks_cluster.this.name
  addon_name   = "aws-ebs-csi-driver"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  # O controller do driver e um Deployment: sem node, o addon fica DEGRADED
  # ate o timeout.
  depends_on = [aws_eks_node_group.this]
}

# StorageClass gp3 do driver CSI. WaitForFirstConsumer cria o volume so quando
# o pod e agendado, na AZ do node escolhido — com Immediate, o volume poderia
# nascer numa AZ e o pod do MongoDB ser agendado na outra, e nunca montar.
#
# Nao e marcada como default: o gp2 que o EKS traz continua default, e quem
# precisa de volume (MongoDB, observabilidade com persistencia) pede esta
# classe pelo nome, via output storage_class_name.

resource "kubernetes_storage_class_v1" "gp3" {
  count = var.ebs_csi_enabled ? 1 : 0

  metadata {
    name = var.storage_class_name
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }

  depends_on = [aws_eks_addon.ebs_csi_driver]
}
