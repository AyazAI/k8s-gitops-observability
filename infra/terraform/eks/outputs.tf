output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS API endpoint. Empty until an apply, which this repository does not run."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 cluster CA data. Empty until an apply, which this repository does not run."
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}
