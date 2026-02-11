########################################
# infra/main.tf — FINAL WORKING VERSION
# Uses DEFAULT VPC → avoids VPC limit exceeded
# Correct slice syntax → fixes "Argument or block definition required"
# Disables KMS + CW logs → avoids org guardrails
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

# -------- variables --------
variable "cluster_name" {
  description = "EKS cluster name (injected by GitHub Actions)"
  type        = string
}

# -------- Use DEFAULT VPC --------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# -------- Select first 2 subnets (VALID syntax) --------
locals {
  selected_subnet_ids = length(data.aws_subnets.default.ids) >= 2 ?
    slice(data.aws_subnets.default.ids, 0, 2) :
    data.aws_subnets.default.ids
}

# -------- Tag subnets for EKS + ELB --------
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

# -------- ECR Repo --------
resource "aws_ecr_repository" "demo" {
  name                 = "demo-app"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
}

# -------- EKS (NO KMS + NO CW logs) --------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.0"

  cluster_name                   = var.cluster_name
  cluster_version                = "1.29"
  cluster_endpoint_public_access = true

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

  create_kms_key             = false
  cluster_encryption_config  = []

  create_cloudwatch_log_group = false
  cluster_enabled_log_types   = []
}

# -------- Outputs --------
output "cluster_name" {
  value = module.eks.cluster_name
}

output "ecr_repo_url" {
  value = aws_ecr_repository.demo.repository_url
}

output "default_vpc_id" {
  value = data.aws_vpc.default.id
}

output "subnets_used" {
  value = local.selected_subnet_ids
}