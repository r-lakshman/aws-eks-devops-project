# MODULE 2 – TERRAFORM INFRASTRUCTURE SETUP

**Free Tier–Conscious Remote State and VPC Networking Configuration**

* **Region:** `ap-south-1` (Mumbai)
* **Project:** `ecommerce-eks`
* **Workstation:** Ubuntu EC2 (`~/aws-eks-project`)

> **Important Clarification:** Using cost-conscious settings does not make an EKS deployment free. EKS control-plane charges, networking, storage, and other AWS services can still incur charges. The configuration below minimizes unnecessary networking costs rather than guaranteeing a zero-cost deployment.

---

## 1. Overview

Module 2 provisions the foundational AWS networking infrastructure required for the EKS project and configures remote Terraform state storage in Amazon S3.

This module creates:

1. S3 remote Terraform state bucket.
2. S3 state versioning and server-side encryption (`AES256`).
3. Native S3 state locking (`use_lockfile = true`).
4. AWS provider configuration.
5. Virtual Private Cloud (`ecommerce-eks-vpc`).
6. Two public subnets (`10.0.1.0/24`, `10.0.2.0/24`).
7. Two private subnets (`10.0.11.0/24`, `10.0.12.0/24`).
8. Internet Gateway (`ecommerce-eks-igw`).
9. Public and private route tables.
10. Route table associations.

### Cost-Conscious Architecture

To reduce networking costs, this version does **not** create:

* **NAT Gateway**
* **NAT Elastic IP**

A NAT Gateway incurs ongoing hourly and data-processing charges. Instead, the EKS worker nodes use **public subnets** with public IP addresses (`map_public_ip_on_launch = true`) and an Internet Gateway.

> **Security Note:** This is a cost-conscious learning configuration, not a recommended production architecture. Restrict security group and cluster endpoint access appropriately.

---

## 2. Important Technical Considerations

Before executing this module:

* Your S3 bucket name must be globally unique.
* Terraform `1.10+` supports native S3 state locking using `use_lockfile = true`.
* Your EC2 IAM role (`ubuntu-eks-devops-role`) must have the required AWS permissions.
* Your Kubernetes version must be supported by EKS in `ap-south-1`.
* Your selected EC2 instance type must be available and eligible under your AWS account's applicable Free Tier offer.
* EKS control-plane usage is not automatically covered by EC2 Free Tier benefits.

---

## 3. Create the S3 Remote State Bucket

### 3.1 Navigate to the Project Directory

```bash
cd ~/aws-eks-project
```

### 3.2 Get AWS Account ID and Set Bucket Name

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="eks-terraform-state-${ACCOUNT_ID}-ap-south-1"

echo "AWS Account: $ACCOUNT_ID"
echo "S3 Bucket: $BUCKET_NAME"
```

### 3.3 Create the S3 Bucket

```bash
aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1
```

*(If the bucket already exists and belongs to your account, do not create it again.)*

### 3.4 Enable Bucket Versioning

```bash
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled
```

### 3.5 Enable Server-Side Encryption

```bash
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

### 3.6 Block Public Access

```bash
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

### 3.7 Verify S3 Configuration

```bash
aws s3api get-bucket-versioning --bucket "$BUCKET_NAME"
aws s3api get-bucket-encryption --bucket "$BUCKET_NAME"
aws s3api get-public-access-block --bucket "$BUCKET_NAME"
```

| Configuration | Expected Value |
| --- | --- |
| **Versioning** | `Enabled` |
| **Encryption** | `AES256` |
| **Public access** | `Blocked` (`true` on all 4 settings) |

---

## 4. Create Terraform Configuration Files

Navigate to the development environment:

```bash
cd ~/aws-eks-project/terraform/environments/dev
```

Expected directory structure:

```text
terraform/
└── environments/
    └── dev/
        ├── terraform.tf
        ├── providers.tf
        ├── variables.tf
        ├── vpc.tf
        ├── eks.tf
        └── outputs.tf
```

### 4.1 Create `terraform.tf`

This configures Terraform, the AWS provider version, and remote S3 state storage:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="eks-terraform-state-${ACCOUNT_ID}-ap-south-1"

cat << EOF > terraform.tf
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "${BUCKET_NAME}"
    key          = "eks-project/dev/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
EOF
```

> **Important:** The S3 bucket must exist before running `terraform init`.

### 4.2 Create `providers.tf`

```bash
cat << 'EOF' > providers.tf
provider "aws" {
  region = var.aws_region
}
EOF
```

### 4.3 Create `variables.tf`

Retain the existing VPC CIDR and subnet configuration:

```bash
cat << 'EOF' > variables.tf
variable "aws_region" {
  default = "ap-south-1"
}

variable "project" {
  default = "ecommerce-eks"
}

variable "kubernetes_version" {
  default = "1.35"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnets" {
  default = [
    "10.0.1.0/24",
    "10.0.2.0/24"
  ]
}

variable "private_subnets" {
  default = [
    "10.0.11.0/24",
    "10.0.12.0/24"
  ]
}
EOF
```

> **Note:** Check the currently supported EKS versions in `ap-south-1` before applying and use the same version across your variables and EKS configuration.

### 4.4 Create `vpc.tf`

This configuration creates two public subnets and two private subnets without a NAT Gateway:

```bash
cat << 'EOF' > vpc.tf
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${var.project}-public-${count.index + 1}"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name                              = "${var.project}-private-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.project}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
EOF
```

> **Important:** Because there is no NAT Gateway, the private subnets do not have outbound internet access in this configuration. Configure your EKS worker nodes to use the **public subnets** (`aws_subnet.public[*].id`).

---

## 5. Verify Terraform Configuration Files

```bash
cd ~/aws-eks-project/terraform/environments/dev
ls -lh
tree .
```

Expected files:

```text
.
├── eks.tf
├── outputs.tf
├── providers.tf
├── terraform.tf
├── variables.tf
└── vpc.tf
```

---

## 6. Verify AWS IAM Permissions

Check your AWS identity, Availability Zones, and S3 bucket access:

```bash
aws sts get-caller-identity
aws ec2 describe-availability-zones --region ap-south-1
aws s3api head-bucket --bucket "$BUCKET_NAME"
```

Your IAM role (`ubuntu-eks-devops-role`) requires permissions for:

* EC2 networking, VPC, subnet, Internet Gateway, and route table operations.
* S3 bucket, object, and state-lock file operations.
* IAM, KMS, OIDC, Auto Scaling, CloudWatch Logs, and EKS operations for Module 3.

---

## 7. Initialize Terraform

```bash
terraform version
terraform init
```

Expected result:

```text
Terraform has been successfully initialized!
```

*(Use `terraform init -reconfigure` only if backend settings change later after confirming the existing remote state location.)*

---

## 8. Format and Validate Terraform

```bash
terraform fmt -recursive
terraform validate
```

Expected output:

```text
Success! The configuration is valid.
```

---

## 9. Review and Apply Infrastructure Changes

Remove any stale `tfplan`, generate a fresh plan with `-out=tfplan`, review it, and apply:

```bash
rm -f tfplan
terraform plan -out=tfplan
terraform show tfplan
terraform apply tfplan
```

*(Do not run another `apply` simultaneously from another EC2 terminal.)*

---

## 10. Verify AWS Infrastructure

### 10.1 Verify VPC and Get VPC ID

```bash
aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=ecommerce-eks-vpc" \
  --region ap-south-1

VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=ecommerce-eks-vpc" \
  --query 'Vpcs[0].VpcId' \
  --output text \
  --region ap-south-1)

echo "$VPC_ID"
```

### 10.2 Verify Subnets and Internet Gateway

```bash
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --region ap-south-1

aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
  --region ap-south-1
```

### 10.3 Verify Terraform State

```bash
terraform state list
```

Expected resources include:

```text
data.aws_availability_zones.available
aws_vpc.main
aws_internet_gateway.igw
aws_subnet.public[0]
aws_subnet.public[1]
aws_subnet.private[0]
aws_subnet.private[1]
aws_route_table.public
aws_route_table.private
aws_route_table_association.public[0]
aws_route_table_association.public[1]
aws_route_table_association.private[0]
aws_route_table_association.private[1]
```

**Module 2 Status:** Terraform remote state and AWS VPC networking setup completed.
