module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.0"

  cluster_name                   = "demo-eks"
  cluster_version                = "1.29"
  cluster_endpoint_public_access = true

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

  # *** IMPORTANT: avoid creating KMS key (fixes your error) ***
  create_kms_key            = false
  cluster_encryption_config = []  # no envelope encryption for demo
}