output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_version" {
  value = aws_eks_cluster.this.version
}

output "cluster_security_group_id" {
  description = "SG criado pelo EKS e anexado ao control plane e aos nós; usado para liberar RDS/Redis"
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}
