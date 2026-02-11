########################################
# infra/main.tf — FINAL ERROR-FREE VERSION
# Uses DEFAULT VPC and ALL its subnets (no slice)
########################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Cluster name passed from GitHub Actions
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

# --------------------------
# USE DEFAULT VPC
# --------------------------
data "aws_vpc" "default" {
  default = true
}

# All subnets of default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# No slicing here → ZERO syntax issues!
locals {
  subnets = data.aws_subnets.default.ids
}

# --------------------------
# TAG SUBNETS FOR EKS + ELB
# --------------------------
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

# --------------------------
# ECR
# --------------------------
resource "aws_ecr_repository" "demo" {
  name = "demo-app"
  image_tag_mutability = "MUTABLE"
}

# --------------------------
# EKS CLUSTER
# --------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.0"

  cluster_name                   = var.cluster_name
  cluster_version                = "1.29"
  cluster_endpoint_public_access = true
  enable_cluster_creator_admin_permissions = true

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = local.subnets

  eks_managed_node_groups = {
    demo = {
      instance_types = ["t3.medium"]
      desired_size   = 1
      min_size       = 1
      max_size       = 1
    }
  }

  enable_irsa = false

  # Disable features blocked by org policies
  create_kms_key            = false
  cluster_encryption_config = []
  create_cloudwatch_log_group = false
  cluster_enabled_log_types   = []
}

output "cluster_name" {
  value = module.eks.cluster_name
}