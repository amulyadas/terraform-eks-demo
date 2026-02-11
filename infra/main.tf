########################################
# infra/main.tf — DEMO (copy-paste)
# Creates:
#   - VPC (2 public subnets)
#   - ECR repo (demo-app)
#   - EKS cluster (1 node)
# Notes:
#   - KMS & CW log group disabled to avoid org guardrails and re-run collisions
#   - cluster_name is a variable so we can pass a unique value from GitHub Actions
########################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "us-east-1"  # change if you need; also update workflow env
}

# -------- variables --------
variable "cluster_name" {
  description = "EKS cluster name (injected by GitHub Actions)"
  type        = string
  default     = "demo-eks"
}

# -------- locals (optional naming helpers) --------
locals {
  region = "us-east-1"
}

# ------------------------------
# VPC (public subnets for demo)
# ------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "demo-vpc"
  cidr = "10.0.0.0/16"

  azs            = ["${local.region}a", "${local.region}b"]
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  enable_dns_support      = true
  enable_dns_hostnames    = true
  map_public_ip_on_launch = true
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

  # Ensure cluster creator (the IAM principal used by Actions) is an admin
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

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

  # Avoid KMS policy issues and CW log group collisions
  create_kms_key             = false
  cluster_encryption_config  = []
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

output "region" {
  value = local.region
}