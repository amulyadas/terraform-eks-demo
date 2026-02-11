########################################
# infra/main.tf — FINAL (no IAM created)
# - Uses DEFAULT VPC (avoids VPC quota)
# - Uses ALL default subnets (no slice errors)
# - Tags subnets for EKS/ELB
# - Plain resources (aws_eks_cluster/node_group) using PRE-APPROVED IAM ROLES
# - S3 backend is configured at init from the workflow (backend args passed there)
########################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  # Backend arguments are passed by the workflow with -backend-config=...
  backend "s3" {}
}

provider "aws" {
  region = "us-east-1"  # keep in sync with the workflow
}

# ---------- Variables injected from the workflow ----------
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_role_arn" {
  description = "Pre-approved IAM Role ARN for EKS Cluster (must have AmazonEKSClusterPolicy)"
  type        = string
}

variable "node_role_arn" {
  description = "Pre-approved IAM Role ARN for EKS Managed Node Group (must have AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy, AmazonEC2ContainerRegistryReadOnly)"
  type        = string
}

# ---------- Use the DEFAULT VPC ----------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Use all subnets (public by default in the default VPC)
locals {
  subnets = data.aws_subnets.default.ids
}

# ---------- Tag subnets so EKS/ELB can use them ----------
resource "aws_ec2_tag" "subnet_cluster" {
  for_each    = toset(local.subnets)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.cluster_name}"
  value       = "shared"
}

resource "aws_ec2_tag" "subnet_public_elb" {
  for_each    = toset(local.subnets)
  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"
}

# ---------- ECR (demo repo) ----------
resource "aws_ecr_repository" "demo" {
  name                 = "demo-app"
  image_tag_mutability = "MUTABLE"
}

# ---------- EKS CLUSTER (NO KMS / NO CW control-plane logs) ----------
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn

  version = "1.29"

  vpc_config {
    subnet_ids = local.subnets
    endpoint_private_access = false
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = [] # disabled to avoid CW log group collisions
}

# ---------- EKS MANAGED NODE GROUP (uses existing node role) ----------
resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "demo"
  node_role_arn   = var.node_role_arn
  subnet_ids      = local.subnets
  ami_type        = "AL2_x86_64"
  capacity_type   = "ON_DEMAND"
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }

  depends_on = [aws_eks_cluster.this]
}

# ---------- Outputs ----------
output "cluster_name"   { value = aws_eks_cluster.this.name }
output "ecr_repo_url"   { value = aws_ecr_repository.demo.repository_url }
output "default_vpc_id" { value = data.aws_vpc.default.id }
output "subnets_used"   { value = local.subnets }