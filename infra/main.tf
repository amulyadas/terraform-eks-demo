########################################
# infra/main.tf — DEMO (uses DEFAULT VPC to avoid VPC quota)
# Creates:
#   - ECR repo (demo-app)
#   - EKS cluster (1 node) in DEFAULT VPC public subnets
# Notes:
#   - No new VPC created (bypasses VpcLimitExceeded)
#   - Auto-tags default VPC subnets for EKS/ELB usage
#   - KMS & CW log group disabled to avoid org guardrails and re-run collisions
#   - cluster_name is provided via TF_VAR_cluster_name from GitHub Actions
########################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "us-east-1"  # change if you need; also update the workflow env
}

# -------- variables --------
variable "cluster_name" {
  description = "EKS cluster name (injected by GitHub Actions)"
  type        = string
  default     = "demo-eks"
}

# -------- use the DEFAULT VPC --------
data "aws_vpc" "default" {
  default = true
}

# All subnets in default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Pick first two subnets for demo (default VPC subnets are public by default)
locals {
  selected_subnet_ids = length(data.aws_subnets.default.ids) >= 2
    ? slice(data.aws_subnets.default.ids, 0, 2)
    : data.aws_subnets.default.ids
}

# -------- Tag subnets so EKS can create ELBs & identify cluster --------
# Tag ALL selected subnets with cluster + public ELB role
resource "aws_ec2_tag" "subnet_cluster" {
  for_each    = toset(local.selected_subnet_ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.cluster_name}"
  value       = "shared"
}

resource "aws_ec2_tag" "subnet_public_elb" {
  for_each    = toset(local.selected_subnet_ids)
  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"
}

# ------------------------------
# ECR repo
# ------------------------------
resource "aws_ecr_repository" "demo" {
  name                 = "demo-app"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = false }
}

# ------------------------------
# EKS cluster (KMS & CW logs disabled for demo)
# ------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.0"

  cluster_name                   = var.cluster_name
  cluster_version                = "1.29"
  cluster_endpoint_public_access = true

  # Give the creator (your GH Actions principal) admin
  enable_cluster_creator_admin_permissions = true

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = local.selected_subnet_ids

  eks_managed_node_groups = {
    demo = {
      instance_types = ["t3.medium"]
      desired_size   = 1
      min_size       = 1
      max_size       = 1
      capacity_type  = "ON_DEMAND"
    }
  }

  enable_irsa = false

  # Avoid DCE KMS policy restrictions
  create_kms_key            = false
  cluster_encryption_config = []

  # Avoid CW log group collisions on re-runs without TF state
  create_cloudwatch_log_group = false
  cluster_enabled_log_types   = []
}

# ------------------------------
# Outputs
# ------------------------------
output "cluster_name" {
  value = module.eks.cluster_name
}

output "ecr_repo_url" {
  value = aws_ecr_repository.demo.repository_url
}

output "vpc_id" {
  value = data.aws_vpc.default.id
}

output "subnet_ids" {
  value = local.selected_subnet_ids
}