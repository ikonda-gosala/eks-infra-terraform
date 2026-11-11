variable "aws_region" {
  type        = string
  default     = "ap-southeast-2"
  description = "The AWS region to deploy your infrastructure"
}

variable "cluster_name" {
  type        = string
  default     = "free-tier-eks"
  description = "Name of your EKS cluster"
}

