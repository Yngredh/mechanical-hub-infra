output "cluster_name" {
  description = "Nome do cluster EKS. Usado em: aws eks update-kubeconfig --name <valor>"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Endpoint do API server do cluster."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_arn" {
  description = "ARN do cluster EKS."
  value       = aws_eks_cluster.this.arn
}

output "cluster_version" {
  description = "Versao do Kubernetes em execucao no cluster."
  value       = aws_eks_cluster.this.version
}

output "cluster_ca_certificate" {
  description = "Certificado da CA do cluster, em base64."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group gerenciado pelo EKS e anexado a todos os nodes do cluster."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "control_plane_security_group_id" {
  description = "Security group proprio do control plane, criado por este modulo."
  value       = aws_security_group.cluster.id
}

output "node_security_group_id" {
  description = "Security group adicional dos nodes, criado por este modulo."
  value       = aws_security_group.nodes.id
}

output "node_group_name" {
  description = "Nome do managed node group."
  value       = aws_eks_node_group.this.node_group_name
}

output "node_group_autoscaling_group_name" {
  description = <<-EOT
    Nome da Auto Scaling Group que sustenta o managed node group.

    Usado pelo modulo app-lb para anexar o target group do NLB interno da
    aplicacao (aws_autoscaling_attachment), em vez de um controller do
    Kubernetes criar o load balancer.
  EOT
  value       = aws_eks_node_group.this.resources[0].autoscaling_groups[0].name
}
