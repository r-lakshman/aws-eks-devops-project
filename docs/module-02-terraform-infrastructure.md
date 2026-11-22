# Module 2 – VPC Networking & Terraform Remote State

**Region:** `ap-south-1` (Mumbai) | **VPC Name:** `ecommerce-eks-vpc` (`10.0.0.0/16`) | **State Bucket:** `eks-terraform-state-<ACCOUNT_ID>-ap-south-1`

This module configures an encrypted, versioned **Amazon S3 backend** for Terraform state and provisions a cost-conscious **VPC** (`10.0.0.0/16`) across two Availability Zones (`ap-south-1a`, `ap-south-1b`) with public/private subnets, an Internet Gateway, and EKS-required subnet tags—avoiding expensive NAT Gateways for dev/lab setups.

## Architecture & Key Parameters

| Parameter | Value | Notes | 
| ----- | ----- | ----- | 
| **AWS Region** | `ap-south-1` | Mumbai | 
| **State S3 Bucket** | `eks-terraform-state-<ACCOUNT_ID>-ap-south-1` | Versioning & AES256 encryption enabled | 
| **VPC CIDR** | `10.0.0.0/16` | Tagged `Name = ecommerce-eks-vpc` | 
| **Public Subnets** | `10.0.1.0/24` (`ap-south-1a`), `10.0.2.0/24` (`ap-south-1b`) | `map_public_ip_on_launch = true`, tagged `kubernetes.io/role/elb = 1` | 
| **Private Subnets** | `10.0.11.0/24` (`ap-south-1a`), `10.0.12.0/24` (`ap-south-1b`) | Tagged `kubernetes.io/role/internal-elb = 1` | 
| **Cluster Tag** | `kubernetes.io/cluster/ecommerce-eks = shared` | Required for AWS Load Balancer Controller subnet auto-discovery | 

## Step 1 – Create the S3 Bucket for Terraform Remote State

Create a versioned, encrypted S3 bucket in `ap-south-1` to store `terraform.tfstate` safely outside Git:

```
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
STATE_BUCKET="eks-terraform-state-${ACCOUNT_ID}-ap-south-1"

aws s3api create-bucket \
  --bucket "${STATE_BUCKET}" \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1 || true

aws s3api put-bucket-versioning \
  --bucket "${STATE_BUCKET}" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "${STATE_BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

aws s3api put-public-access-block \
  --bucket "${STATE_BUCKET}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

* **Verification:** `aws s3api head-bucket --bucket "${STATE_BUCKET}"` succeeds with no error output.

## Step 2 – Create the Reusable VPC Terraform Module (`modules/vpc`)

Create the VPC module files (`variables.tf`, `main.tf`, `outputs.tf`) under `~/aws-eks-project/terraform/modules/vpc`:

```
VPC_MOD_DIR=~/aws-eks-project/terraform/modules/vpc
mkdir -p "$VPC_MOD_DIR"

cat << 'EOF' > "$VPC_MOD_DIR/variables.tf"
variable "vpc_name" {
  type    = string
  default = "ecommerce-eks-vpc"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "cluster_name" {
  type    = string
  default = "ecommerce-eks"
}

variable "azs" {
  type    = list(string)
  default = ["ap-south-1a", "ap-south-1b"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.11.0/24", "10.0.12.0/24"]
}
EOF

cat << 'EOF' > "$VPC_MOD_DIR/main.tf"
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.vpc_name
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.vpc_name}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${var.vpc_name}-public-${var.azs[count.index]}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name                                        = "${var.vpc_name}-private-${var.azs[count.index]}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.vpc_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
EOF

cat << 'EOF' > "$VPC_MOD_DIR/outputs.tf"
output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}
EOF
```

* **Verification:** `ls -lh "$VPC_MOD_DIR"` confirms `variables.tf`, `main.tf`, and `outputs.tf` exist.

## Step 3 – Configure `environments/dev` Backend & Provision the VPC

Create `backend.tf`, `providers.tf`, `main.tf`, and `outputs.tf` in `~/aws-eks-project/terraform/environments/dev`, initialize Terraform, and apply the VPC configuration:

```
DEV_DIR=~/aws-eks-project/terraform/environments/dev
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
STATE_BUCKET="eks-terraform-state-${ACCOUNT_ID}-ap-south-1"
mkdir -p "$DEV_DIR"

cat << EOF > "$DEV_DIR/backend.tf"
terraform {
  backend "s3" {
    bucket  = "${STATE_BUCKET}"
    key     = "dev/terraform.tfstate"
    region  = "ap-south-1"
    encrypt = true
  }
}
EOF

cat << 'EOF' > "$DEV_DIR/providers.tf"
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}
EOF

cat << 'EOF' > "$DEV_DIR/main.tf"
module "vpc" {
  source       = "../../modules/vpc"
  vpc_name     = "ecommerce-eks-vpc"
  vpc_cidr     = "10.0.0.0/16"
  cluster_name = "ecommerce-eks"
}
EOF

cat << 'EOF' > "$DEV_DIR/outputs.tf"
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}
EOF

cd "$DEV_DIR"
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

* **Verification:** `terraform apply` completes with `Apply complete!` and prints `vpc_id = "vpc-..."` along with the public and private subnet IDs.
