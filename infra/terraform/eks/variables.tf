variable "aws_region" {
  type        = string
  description = "AWS region. This configuration is not applied."
  default     = "us-east-1"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name."
  default     = "portfolio-sample"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version for the EKS control plane."
  default     = "1.35"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Existing subnet IDs. Required for an apply, which this repository does not run."
  default     = []
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}
