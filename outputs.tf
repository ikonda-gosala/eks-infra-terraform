output "cluster_endpoint" {
  value       = aws_eks_cluster.this.endpoint
  description = "The URL endpoint for your EKS cluster API server"
}

output "cluster_name" {
  value       = aws_eks_cluster.this.name
  description = "The name of the EKS cluster"
}

