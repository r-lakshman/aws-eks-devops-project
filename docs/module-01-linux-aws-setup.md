# Module 1 – Linux & AWS Environment Setup

**Region:** `ap-south-1` | **Project:** `ecommerce-eks` | **Workstation:** Ubuntu EC2 (`~/aws-eks-project`)

This module prepares the Ubuntu operating system, creates an organized workspace for every part of the project, installs the required DevOps CLI tools, and configures an EC2 IAM instance profile (`ubuntu-eks-devops-role`) with all permissions needed for Terraform provisioning and EKS cluster/node-group management.

---

## 1. Create the Project Directory Structure

**Purpose:** Keeps Terraform, application code, Helm charts, Kubernetes manifests, Jenkins files, and scripts cleanly separated.

```bash
mkdir -p ~/aws-eks-project/{terraform/environments/dev,application/ecommerce-app/src/main/{java/com/example/ecommerce,resources},helm/ecommerce/templates,kubernetes,jenkins,scripts}

cd ~/aws-eks-project
```

- **Verification:** Your current directory is `~/aws-eks-project`.

---

## 2. Update Ubuntu and Install Core Packages, Docker, Java 17 & Maven

**Purpose:** Ensures system libraries are current and installs container, runtime, and build tools on Ubuntu.

### 2.1 Update Ubuntu
```bash
sudo apt clean
sudo apt update
sudo apt upgrade -y
```

### 2.2 Install Required Packages
```bash
sudo apt install -y \
  curl wget unzip git jq tree vim zip \
  ca-certificates gnupg software-properties-common \
  docker.io maven openjdk-17-jdk
```

### 2.3 Configure Docker Group and Service
```bash
sudo usermod -aG docker ubuntu
sudo systemctl enable --now docker
sudo systemctl status docker --no-pager
```

### 2.4 Verify Package Installations
```bash
docker --version
java -version
mvn -version
git --version
tree --version
```

> **Note:** Log out and reconnect to the EC2 instance (or run `newgrp docker`) for `docker` group membership to take effect without `sudo`.

- **Verification:** `docker`, `java` (17), `mvn`, `git`, and `tree` print valid versions and `docker` service is `active (running)`.

---

## 3. Verify the Project Directory Structure

**Purpose:** Confirms all required project directories exist.

```bash
cd ~/aws-eks-project
tree -L 4 .
```

Expected output:

```text
.
├── application
│   └── ecommerce-app
│       └── src
│           └── main
├── helm
│   └── ecommerce
│       └── templates
├── jenkins
├── kubernetes
├── scripts
└── terraform
    └── environments
        └── dev
```

- **Verification:** All six top-level directories (`application`, `helm`, `jenkins`, `kubernetes`, `scripts`, `terraform`) appear in the tree output.

---

## 4. Install AWS CLI v2, Terraform, kubectl, Helm, and eksctl

**Purpose:** Installs the CLI tools required to provision AWS infrastructure, manage EKS clusters, and package Helm releases.

### 4.1 Install AWS CLI v2
```bash
curl -s "[https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip](https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip)" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp
sudo /tmp/aws/install --update
rm -rf /tmp/aws /tmp/awscliv2.zip

aws --version
```

### 4.2 Install Terraform (`>= 1.10.0`)
```bash
wget -qO- [https://apt.releases.hashicorp.com/gpg](https://apt.releases.hashicorp.com/gpg) | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] [https://apt.releases.hashicorp.com](https://apt.releases.hashicorp.com) $(. /etc/os-release && echo $VERSION_CODENAME) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt update
sudo apt install -y terraform

terraform version
```

### 4.3 Install `kubectl`
```bash
curl -sLO "[https://dl.k8s.io/release/$(curl](https://dl.k8s.io/release/$(curl) -Ls [https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl](https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl)"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl

kubectl version --client
```

### 4.4 Install Helm
```bash
curl -fsSL [https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3](https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3) | bash

helm version
```

### 4.5 Install `eksctl`
```bash
curl -sLO "[https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname](https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname) -s)_amd64.tar.gz"
tar -xzf eksctl_$(uname -s)_amd64.tar.gz -C /tmp
sudo install /tmp/eksctl /usr/local/bin/eksctl
rm -f eksctl_$(uname -s)_amd64.tar.gz /tmp/eksctl

eksctl version
```

- **Verification:** Each CLI prints its version without errors (`aws-cli/2.x`, `Terraform v1.10+`, `kubectl`, `Helm v3.x`, `eksctl`).

---

## 5. Authenticate AWS CLI Using an EC2 IAM Instance Profile

**Purpose:** Attaches `ubuntu-eks-devops-role` to your Ubuntu EC2 workstation so AWS CLI and Terraform authenticate automatically using temporary credentials without static access keys.

First, check whether an IAM role is already attached:

```bash
aws sts get-caller-identity
```

If this returns `NoCredentials` or lacks required permissions, follow the steps below.

### 5.1 Create the IAM Role
1. Navigate to **AWS Console → IAM → Roles → Create role**.
2. Set **Trusted entity type** to **AWS service** and **Use case** to **EC2**, then click **Next**.

### 5.2 Create the Custom IAM Policy
1. Navigate to **AWS Console → IAM → Policies → Create policy → JSON**.
2. Paste the policy below (includes unique `Sid`s, scoped `iam:CreateServiceLinkedRole`, KMS/OIDC/InstanceProfile discovery, Auto Scaling inspection, and S3 Terraform state/lock permissions):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AWSResourceDiscoveryAndRefresh",
      "Effect": "Allow",
      "Action": [
        "eks:*",
        "ec2:*",
        "ecr:*",
        "logs:*",
        "autoscaling:*",
        "iam:GetRole",
        "iam:ListRoles",
        "iam:ListPolicies",
        "iam:ListRolePolicies",
        "iam:GetRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:ListInstanceProfilesForRole",
        "iam:GetInstanceProfile",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListPolicyVersions",
        "s3:ListAllMyBuckets",
        "cloudformation:ListStacks",
        "cloudformation:DescribeStacks"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMCreateModifyForEKS",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:TagPolicy",
        "iam:UntagPolicy",
        "iam:CreateOpenIDConnectProvider",
        "iam:DeleteOpenIDConnectProvider",
        "iam:GetOpenIDConnectProvider",
        "iam:ListOpenIDConnectProviders",
        "iam:TagOpenIDConnectProvider"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CreateEKSServiceLinkedRole",
      "Effect": "Allow",
      "Action": "iam:CreateServiceLinkedRole",
      "Resource": "arn:aws:iam::*:role/aws-service-role/[eks.amazonaws.com/AWSServiceRoleForAmazonEKS](https://eks.amazonaws.com/AWSServiceRoleForAmazonEKS)*"
    },
    {
      "Sid": "PassRoleToEKSAndEC2",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": [
            "eks.amazonaws.com",
            "ec2.amazonaws.com"
          ]
        }
      }
    },
    {
      "Sid": "KMSPermissionsForEKS",
      "Effect": "Allow",
      "Action": [
        "kms:CreateKey",
        "kms:CreateAlias",
        "kms:DeleteAlias",
        "kms:ListAliases",
        "kms:DescribeKey",
        "kms:GetKeyPolicy",
        "kms:PutKeyPolicy",
        "kms:TagResource",
        "kms:UntagResource",
        "kms:ListResourceTags",
        "kms:ScheduleKeyDeletion",
        "kms:EnableKeyRotation"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SSMGetAMIParameterForEKS",
      "Effect": "Allow",
      "Action": "ssm:GetParameter",
      "Resource": "*"
    },
    {
      "Sid": "TerraformS3BucketPermissions",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:PutBucketVersioning",
        "s3:GetBucketVersioning",
        "s3:PutEncryptionConfiguration",
        "s3:GetEncryptionConfiguration",
        "s3:PutBucketPublicAccessBlock",
        "s3:GetBucketPublicAccessBlock",
        "s3:PutBucketPolicy",
        "s3:GetBucketPolicy",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:PutBucketTagging",
        "s3:GetBucketTagging"
      ],
      "Resource": "arn:aws:s3:::eks-terraform-state-*"
    },
    {
      "Sid": "TerraformS3ObjectPermissions",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::eks-terraform-state-*/*"
    }
  ]
}
```

3. Click **Next**, enter policy name `ubuntu-eks-devops-policy`, and click **Create policy**.

### 5.3 Attach Policies, Tag Role, and Associate With EC2
1. Back in the role creation tab, attach `ubuntu-eks-devops-policy` (and optionally `AmazonSSMManagedInstanceCore`), then click **Next**.
2. Set **Role name** to `ubuntu-eks-devops-role` and add tags:

| Key | Value |
|---|---|
| `Name` | `ubuntu-eks-devops-role` |
| `Project` | `AWS-EKS-DevOps` |
| `Environment` | `Dev` |
| `Owner` | `DevOps` |
| `ManagedBy` | `Terraform` |
| `Purpose` | `Ubuntu-EC2-DevOps-Workstation` |

3. Click **Create role**.
4. Open **AWS Console → EC2 → Instances**, select your Ubuntu workstation (`ubuntu-eks-devops-host`), click **Actions → Security → Modify IAM role**, select `ubuntu-eks-devops-role`, and click **Update IAM role**.

### 5.4 Verify IAM Role, Default Region, and EKS API Access
```bash
aws sts get-caller-identity

aws configure set region ap-south-1
aws configure get region

aws eks list-clusters --region ap-south-1
```

- **Verification:** `get-caller-identity` shows `assumed-role/ubuntu-eks-devops-role/...`, default region is `ap-south-1`, and `aws eks list-clusters` returns JSON without `AccessDenied`.

---

## 6. Final Verification Checklist

```bash
aws --version
terraform version
kubectl version --client
helm version
eksctl version
docker --version
java -version
mvn -version
git --version
tree --version

aws sts get-caller-identity
aws configure get region

cd ~/aws-eks-project
tree -L 4 .
```

**Module 1 Status:** Ubuntu workstation packages, CLI tools, directory workspace, and `ubuntu-eks-devops-role` IAM permissions are verified and ready for Module 2.
