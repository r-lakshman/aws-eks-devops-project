module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.project
  kubernetes_version = var.kubernetes_version

  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.private[*].id

  endpoint_public_access  = true
  endpoint_private_access = true

  enable_cluster_creator_admin_permissions = true

  addons = {
    coredns            = {}
    kube-proxy         = {}
    vpc-cni            = {}
    aws-ebs-csi-driver = {}
  }

  eks_managed_node_groups = {
    application = {
      name           = "application-nodes"
      instance_types = ["t3.small"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2
      subnet_ids     = aws_subnet.private[*].id
    }
  }

  tags = {
    Environment = "dev"
    Project     = var.project
  }
}

resource "aws_ecr_repository" "app" {
  name                 = "ecommerce-app"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}
