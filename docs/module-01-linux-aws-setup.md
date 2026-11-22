# Module 1 – Workstation Setup, IAM Role & Project Scaffolding

**Region:** `ap-south-1` (Mumbai) | **Workstation:** Ubuntu Server 24.04 LTS EC2 | **IAM Role:** `ubuntu-eks-devops-role`

This module prepares the Ubuntu Server 24.04 LTS EC2 workstation in `ap-south-1` with all required DevOps CLI tools (`awscli`, `terraform`, `kubectl`, `eksctl`, `helm`, `docker`, `openjdk-17`, `maven`, `git`), verifies IAM instance profile credentials, creates the `ecommerce-app` Amazon ECR repository, and initializes the `~/aws-eks-project` directory layout.

## Architecture & Key Parameters

| Parameter | Value | Notes | 
| ----- | ----- | ----- | 
| **AWS Region** | `ap-south-1` | Mumbai | 
| **EC2 Workstation OS** | Ubuntu Server 24.04 LTS | Attached IAM Instance Profile (`ubuntu-eks-devops-role`) | 
| **Core CLI Stack** | AWS CLI v2, Terraform, `kubectl`, `eksctl`, Helm | Used to provision and manage EKS infrastructure | 
| **Build & Container Stack** | OpenJDK 17, Maven, Docker | Used to compile, test, and containerize `ecommerce-app` | 
| **Project Root** | `~/aws-eks-project` | Organized by `terraform/`, `application/`, `kubernetes/`, `helm/`, `jenkins/`, `docs/` | 

## Step 1 – Install DevOps & Build CLI Tools on Ubuntu 24.04 LTS

Update apt packages and install Git, Docker, OpenJDK 17, Maven, AWS CLI v2, Terraform, `kubectl`, `eksctl`, and Helm:

```
sudo apt-get update -y
sudo apt-get install -y curl unzip gnupg software-properties-common git jq docker.io openjdk-17-jdk maven

# Enable Docker and allow the ubuntu user to run Docker commands
sudo systemctl enable --now docker
sudo usermod -aG docker ubuntu

# Install AWS CLI v2
curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -qo /tmp/awscliv2.zip -d /tmp
sudo /tmp/aws/install --update
rm -rf /tmp/aws /tmp/awscliv2.zip

# Install Terraform
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update -y && sudo apt-get install -y terraform

# Install kubectl (v1.36)
curl -LO "https://dl.k8s.io/release/v1.36.0/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl

# Install eksctl
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz"
tar -xzf eksctl_Linux_amd64.tar.gz -C /tmp && rm -f eksctl_Linux_amd64.tar.gz
sudo mv /tmp/eksctl /usr/local/bin

# Install Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

* **Verification:** Run `aws --version && terraform -version && kubectl version --client && eksctl version && helm version && java -version && mvn -version && docker --version` to confirm every binary is installed and executable.

## Step 2 – Configure Default Region & Verify EC2 IAM Instance Profile

Set the default AWS CLI region to `ap-south-1` and verify that the EC2 instance assumes `ubuntu-eks-devops-role` cleanly without hardcoded AWS access keys:

```
aws configure set default.region ap-south-1
aws configure set default.output json

aws sts get-caller-identity
```

> **Note:** Ensure `ubuntu-eks-devops-role` includes permissions for EC2/VPC, EKS, IAM, S3, ECR, CloudFormation (if using `eksctl`), and Secrets Manager (`production/*`).

* **Verification:** `aws sts get-caller-identity` outputs your AWS `Account` ID and an `Arn` referencing `assumed-role/ubuntu-eks-devops-role/...`.

## Step 3 – Create the Amazon ECR Repository (`ecommerce-app`)

Create the private Amazon ECR repository in `ap-south-1` with image scanning enabled on push:

```
aws ecr create-repository \
  --repository-name ecommerce-app \
  --image-scanning-configuration scanOnPush=true \
  --region ap-south-1 || true

aws ecr describe-repositories --repository-names ecommerce-app --region ap-south-1
```

* **Verification:** `aws ecr describe-repositories` returns the `repositoryUri` (`<ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/ecommerce-app`).

## Step 4 – Scaffold the `~/aws-eks-project` Directory Structure

Create the standardized folder layout used across Modules 2 through 12:

```
mkdir -p ~/aws-eks-project/{terraform/modules/vpc,terraform/modules/eks,terraform/environments/dev}
mkdir -p ~/aws-eks-project/application/ecommerce-app/src/{main/java/com/example/ecommerce,main/resources,test/java/com/example/ecommerce}
mkdir -p ~/aws-eks-project/{kubernetes,helm/ecommerce/templates,jenkins,scripts,docs}

tree -L 3 ~/aws-eks-project 2>/dev/null || find ~/aws-eks-project -maxdepth 3 -type d | sort
```

* **Verification:** All project directories (`terraform/`, `application/`, `kubernetes/`, `helm/`, `jenkins/`, `scripts/`, `docs/`) are created under `~/aws-eks-project`.
