# ==========================================
# TERRAFORM & PROVIDER CONFIG
# ==========================================
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # REMOTE STATE BACKEND LINKING
  backend "s3" {
    bucket         = "end-to-end-devops-prjct" # Replace with your actual S3 bucket name
    key            = "eks/terraform.tfstate"
    region         = "ap-southeast-2"                      # Matches your GHA pipeline region
    dynamodb_table = "dynamodb-for-state-locking" # Replace with your actual DynamoDB table name
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# ==========================================
# BUDGET NETWORKING (No expensive NAT Gateways)
# ==========================================
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "eks-free-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags                    = { "kubernetes.io/role/elb" = "1" }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
  tags                    = { "kubernetes.io/role/elb" = "1" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "pub1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "pub2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# ==========================================
# EKS CONTROL PLANE & NODE GROUP
# ==========================================
resource "aws_iam_role" "cluster" {
  name = "eks-cluster-mini-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "eks.amazonaws.com" } }] # Fixed typo from "://"
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  vpc_config { subnet_ids = [aws_subnet.public_1.id, aws_subnet.public_2.id] }
  depends_on = [aws_iam_role_policy_attachment.cluster]
}

resource "aws_iam_role" "nodes" {
  name = "eks-nodes-mini-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }] # Fixed typo from "://"
  })
}

resource "aws_iam_role_policy_attachment" "node_policies" {
  for_each   = toset(["arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy", "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy", "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"])
  role       = aws_iam_role.nodes.name
  policy_arn = each.value
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "practice-nodes"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }
  instance_types = ["t3.medium"] # Smallest required instance type to host Prometheus + Grafana
  depends_on     = [aws_iam_role_policy_attachment.node_policies]
}
