# Module 3 – Amazon EKS Cluster & Managed Node Group

**Region:** `ap-south-1` (Mumbai) | **Cluster:** `ecommerce-eks` (Kubernetes `1.36`) | **Node Group:** `application-nodes` (`t3.small`)

This module defines the Terraform IAM roles and EKS resources to provision the **`ecommerce-eks`** control plane and the **`application-nodes`** managed EC2 node group inside our custom VPC in `ap-south-1`, then configures `kubectl` to connect to the cluster.

## Architecture & Key Parameters

| Parameter | Value | Notes | 
| ----- | ----- | ----- | 
| **Cluster Name** | `ecommerce-eks` | EKS Control Plane running Kubernetes `1.36` | 
| **Cluster IAM Role** | `ecommerce-eks-cluster-role` | Attached `AmazonEKSClusterPolicy` | 
| **Node Group Name** | `application-nodes` | Managed EC2 worker nodes | 
| **Instance Type** | `t3.small` | Cost-conscious sizing (`desired: 1`, `min: 1`, `max: 3`) | 
| **Node IAM Role** | `ecommerce-eks-node-role` | Attached `WorkerNodePolicy`, `CNI_Policy`, `ContainerRegistryReadOnly` | 

## Step 1 – Create EKS Cluster & Node Group Terraform Module (`modules/eks`)

Create the reusable EKS Terraform module directory and define `variables.tf`, `main.tf`, and `outputs.tf`:

```
EKS_MOD_DIR=~/aws-eks-project/terraform/modules/eks
mkdir -p "$EKS_MOD_DIR"

cat << 'EOF' > "$EKS_MOD_DIR/variables.tf"
variable "cluster_name" {
  type        = string
  description = "Name of the Amazon EKS cluster"
}

variable "cluster_version" {
  type        = string
  default     = "1.36"
  description = "Kubernetes version for the EKS control plane"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for the EKS cluster and node group"
}

variable "instance_types" {
  type        = list(string)
  default     = ["t3.small"]
  description = "EC2 instance types for the managed node group"
}

variable "desired_size" {
  type    = number
  default = 1
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 3
}
EOF

cat << 'EOF' > "$EKS_MOD_DIR/main.tf"
# --- EKS Control Plane IAM Role ---
resource "aws_iam_role" "eks_cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# --- EKS Cluster ---
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# --- Managed Node Group IAM Role ---
resource "aws_iam_role" "eks_nodes" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "ecr_readonly_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

# --- EKS Managed Node Group ---
resource "aws_eks_node_group" "application_nodes" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "application-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.subnet_ids
  instance_types  = var.instance_types
  capacity_type   = "ON_DEMAND"

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.worker_node_policy,
    aws_iam_role_policy_attachment.cni_policy,
    aws_iam_role_policy_attachment.ecr_readonly_policy,
  ]
}
EOF

cat << 'EOF' > "$EKS_MOD_DIR/outputs.tf"
output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_oidc_issuer_url" {
  value = aws_eks_cluster.this.identity[0].oidc[0].issuer
}
EOF
```

* **Verification:** `ls -lh "$EKS_MOD_DIR"` confirms `variables.tf`, `main.tf`, and `outputs.tf` are present.

## Step 2 – Wire the EKS Module into `environments/dev` & Apply

Add the `eks` module block to `~/aws-eks-project/terraform/environments/dev/main.tf` and apply the configuration:

```
DEV_DIR=~/aws-eks-project/terraform/environments/dev

cat << 'EOF' >> "$DEV_DIR/main.tf"

module "eks" {
  source          = "../../modules/eks"
  cluster_name    = "ecommerce-eks"
  cluster_version = "1.36"
  subnet_ids      = module.vpc.public_subnet_ids
  instance_types  = ["t3.small"]
  desired_size    = 1
  min_size        = 1
  max_size        = 3
}
EOF

cat << 'EOF' >> "$DEV_DIR/outputs.tf"

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}
EOF

cd "$DEV_DIR"
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

> **Note:** Provisioning the EKS control plane and managed node group typically takes **10–15 minutes**. Because this cost-conscious VPC uses public subnets with auto-assigned public IPs instead of a NAT Gateway, `subnet_ids` uses `module.vpc.public_subnet_ids` so worker nodes can pull container images from ECR and communicate with the EKS API.

* **Verification:** `terraform apply` finishes with `Apply complete!` and prints `eks_cluster_name = "ecommerce-eks"`.

## Step 3 – Configure `kubectl` and Verify Cluster Nodes

Update `~/.kube/config` for `ecommerce-eks` in `ap-south-1` and verify node registration and system pods:

```
aws eks update-kubeconfig --region ap-south-1 --name ecommerce-eks

kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -n kube-system
```

* **Verification:** `kubectl get nodes` lists one `t3.small` worker node in `Ready` state running Kubernetes `v1.36.x`, and core system pods (`coredns`, `kube-proxy`, `aws-node`) are `Running`.
