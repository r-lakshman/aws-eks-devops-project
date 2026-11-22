# AWS EKS E-Commerce DevOps Project

**AWS Region:** `ap-south-1` (Mumbai) | **Cluster:** `ecommerce-eks` (Kubernetes `v1.36`) | **Workstation:** Ubuntu Server 24.04 LTS EC2

## 🚀 Project Overview

This repository demonstrates an end-to-end, production-aligned DevOps implementation for deploying a containerized Java 17 Spring Boot microservice (`ecommerce-app`) onto **Amazon Elastic Kubernetes Service (EKS)** in `ap-south-1`.

The project covers the complete cloud-native lifecycle:

- **Infrastructure as Code (IaC):** Modular Terraform provisioning of a custom VPC (`ecommerce-eks-vpc`) and EKS cluster (`ecommerce-eks`) with an encrypted S3 remote state backend.
- **Identity & Access Management:** Keyless EC2 workstation authentication (`ubuntu-eks-devops-role`) and fine-grained **IAM Roles for Service Accounts (IRSA)** via OIDC for the AWS Load Balancer Controller and CloudWatch Observability.
- **Application & Containerization:** Spring Boot REST microservice compiled with Maven, packaged into a multi-stage, non-root Alpine Docker image, and stored in Amazon ECR.
- **Kubernetes & Helm Packaging:** Namespace isolation (`production`), RBAC, NetworkPolicies, PodDisruptionBudgets, Horizontal Pod Autoscaling (HPA), and atomic Helm rollouts behind an AWS Application Load Balancer (ALB).
- **CI/CD, Security & Observability:** Declarative Jenkins pipeline with SonarQube and Trivy scanning, AWS Secrets Manager integration, Prometheus/Grafana monitoring (`kube-prometheus-stack`), and CloudWatch Container Insights.

## 🏗️ Architecture & Workflow

```text
+---------------------------------------------------------------------------------------------------+
|                        UBUNTU EC2 WORKSTATION (ubuntu-eks-devops-host, ap-south-1)                  |
|                         IAM Role: ubuntu-eks-devops-role (No static keys)                          |
|                                                                                                   |
|  aws-eks-project/                                                                                 |
|  ├── docs/                  --> prerequisites + module-01..12.md                                  |
|  ├── terraform/envs/dev/    --> providers.tf, terraform.tf, variables.tf, vpc.tf, eks.tf,         |
|  │                              outputs.tf, tfplan                                                |
|  ├── application/           --> Spring Boot (pom.xml, src/main, target/*.jar, Dockerfile)        |
|  │   └── ecommerce-app                                                                            |
|  ├── kubernetes/            --> rbac.yaml, network-policy.yaml, pdb.yaml                          |
|  ├── helm/ecommerce/        --> Chart.yaml, values.yaml, templates/{deployment,service,ingress,hpa}|
|  └── jenkins/               --> Jenkinsfile / CI-CD pipeline assets                               |
+------------------------------------+----------------------------------+---------------------------+
                                     |                                  |
             (1) Terraform State     |          (2) Build & Push        |          (3) CI/CD
                 & Infra             |              Container           |              Pipeline
                                     v                                  v
+------------------------------------+----------------------------------+---------------------------+
|                                     AWS CLOUD (ap-south-1 - Mumbai)                               |
|                                                                                                   |
|  +------------------------------+   +-------------------------------+   +----------------------+  |
|  | S3 Remote State Bucket       |   | Amazon ECR                    |   | AWS Secrets Manager  |  |
|  | eks-terraform-state-...      |   | ecommerce-app                 |   | production/          |  |
|  +--------------+---------------+   +---------------+---------------+   | db-password          |  |
|                 |                                   |                   +----------+-----------+  |
|                 v                                   |                              |              |
|  +----------------------------------------------+   |                              |              |
|  | VPC (ecommerce-eks-vpc)                      |   |                              |              |
|  |  Public + Private Subnets, IGW (No NAT GW)   |   |                              |              |
|  |  +----------------------------------------+  |   |                              |              |
|  |  | EKS Cluster: ecommerce-eks (v1.36)     |  |   |                              |              |
|  |  |  OIDC / IRSA & AWS LB Controller       |<--+---+ (Pull Image)                 |              |
|  |  |                                        |      |                              |              |
|  |  |  Node Group: application-nodes         |      |                              |              |
|  |  |   (t3.small)                           |      |                              |              |
|  |  |   - Helm: deployment, service,         |      |                              |              |
|  |  |     ingress (ALB), hpa                 |      |                              |              |
|  |  |   - K8s: rbac, network-policy, pdb     |      |                              |              |
|  |  |   - Monitoring: Prometheus/Grafana &   |      |                              |              |
|  |  |     CloudWatch Agent (IRSA)          |      |                              |              |
|  |  +----------------------------------------+  |      |                              |              |
|  +----------------------------------------------+      |                              |              |
+--------------------------------------------------------+------------------------------+--------------+
                                                         |                              |
                                                         v                              v
                                             +-----------------------+      +--------------------+
                                             | GitHub Repository     |      | CloudWatch & Logs  |
                                             | 12 Modules + Code     |      | Container Insights |
                                             +-----------------------+      +--------------------+
```

## 🛠️ Technologies Used

| Category | Technology / Service | Role in Project |
| :--- | :--- | :--- |
| **Cloud Platform** | Amazon Web Services (`ap-south-1`) | Cloud infrastructure, IAM, networking, load balancing, and managed services |
| **Container Orchestration** | Amazon EKS (`v1.36`) & Kubernetes | Managed Kubernetes control plane and `t3.small` worker node group |
| **Infrastructure as Code** | Terraform (`>= 1.6`) & Amazon S3 | Declarative VPC and EKS provisioning with encrypted remote state |
| **Ingress & Networking** | AWS Load Balancer Controller & VPC | Automated internet-facing ALB provisioning via Kubernetes `Ingress` |
| **Application Stack** | Java 17, Spring Boot `3.4.3`, Maven | REST microservice with Spring Boot Actuator health/metrics endpoints |
| **Containerization & Registry** | Docker & Amazon ECR | Multi-stage non-root Alpine container image builds and private image hosting |
| **Package Management** | Helm v3 | Templated, versioned, atomic Kubernetes releases and rollbacks |
| **CI/CD & Code Quality** | Jenkins, SonarQube, Trivy, GitHub | Automated build, static analysis, CVE image scanning, and EKS deployment |
| **Security & Secrets** | IAM (IRSA/OIDC), RBAC, NetworkPolicy, PDB, AWS Secrets Manager | Least-privilege pod permissions, traffic isolation, availability, and secret storage |
| **Monitoring & Logging** | Prometheus, Grafana (`kube-prometheus-stack`), CloudWatch Container Insights & Fluent Bit | Cluster/pod metrics visualization and centralized log aggregation |
| **Workstation OS** | Ubuntu Server 24.04 LTS | Dedicated EC2 DevOps control host |

## 📁 Project Directory Structure

```text
aws-eks-project/
│
├── application/
│   └── ecommerce-app/
│       ├── Dockerfile
│       ├── pom.xml
│       ├── src/
│       │   └── main/
│       └── target/
│           ├── classes/
│           ├── ecommerce-app-1.0.0.jar
│           ├── ecommerce-app-1.0.0.jar.original
│           ├── generated-sources/
│           ├── maven-archiver/
│           └── maven-status/
│
├── docs/
│   ├── module-01-linux-aws-setup.md
│   ├── module-02-terraform-infrastructure.md
│   ├── module-03-eks-cluster-creation.md
│   ├── module-04-eks-addons-networking.md
│   ├── module-05-application-development.md
│   ├── module-06-docker-ecr.md
│   ├── module-07-kubernetes-deployment.md
│   ├── module-08-helm-deployment.md
│   ├── module-09-jenkins-cicd.md
│   ├── module-10-production-security.md
│   ├── module-11-monitoring-logging.md
│   ├── module-12-testing-troubleshooting.md
│   └── prerequisites_ubuntu_ec2_workstation_iam_setup.md
│
├── helm/
│   └── ecommerce/
│       ├── Chart.yaml
│       ├── templates/
│       │   ├── deployment.yaml
│       │   ├── hpa.yaml
│       │   ├── ingress.yaml
│       │   └── service.yaml
│       └── values.yaml
│
├── ion/
│
├── jenkins/
│
├── kubernetes/
│   ├── network-policy.yaml
│   ├── pdb.yaml
│   └── rbac.yaml
│
├── scripts/
│
└── terraform/
    └── environments/
        └── dev/
            ├── eks.tf
            ├── outputs.tf
            ├── providers.tf
            ├── terraform.tf
            ├── tfplan
            ├── variables.tf
            └── vpc.tf
```

## 📚 Project Modules & Documentation

| Step / Module | Guide | Summary |
| :--- | :--- | :--- |
| **Prerequisites** | [Ubuntu EC2 Workstation & IAM Setup](./docs/prerequisites_ubuntu_ec2_workstation_iam_setup.md) | Launch Ubuntu 24.04 EC2 in `ap-south-1`, create `ubuntu-eks-devops-role`, and connect via EC2 Instance Connect, SSM, or SSH |
| **Module 01** | [Linux and AWS Setup](./docs/module-01-linux-aws-setup.md) | Install DevOps CLI tools (`aws`, `terraform`, `kubectl`, `eksctl`, `helm`, `docker`, `mvn`), verify IAM role, and create ECR repo |
| **Module 02** | [Terraform Infrastructure](./docs/module-02-terraform-infrastructure.md) | Configure S3 remote state backend and provision the `ecommerce-eks-vpc` (`10.0.0.0/16`) across two Availability Zones |
| **Module 03** | [EKS Cluster Creation](./docs/module-03-eks-cluster-creation.md) | Provision the `ecommerce-eks` (`v1.36`) control plane and `application-nodes` (`t3.small`) managed node group via Terraform |
| **Module 04** | [EKS Add-ons and Networking](./docs/module-04-eks-addons-networking.md) | Associate IAM OIDC provider, configure IRSA, and deploy the AWS Load Balancer Controller via Helm |
| **Module 05** | [Application Development](./docs/module-05-application-development.md) | Build and verify the Java 17 Spring Boot `ecommerce-app` microservice with Actuator health endpoints |
| **Module 06** | [Docker and Amazon ECR](./docs/module-06-docker-ecr.md) | Package `ecommerce-app` into a multi-stage non-root Alpine container image and push tag `1.0.0` to Amazon ECR |
| **Module 07** | [Kubernetes Deployment](./docs/module-07-kubernetes-deployment.md) | Create the `production` namespace and apply baseline RBAC, `NetworkPolicy`, and `PodDisruptionBudget` manifests |
| **Module 08** | [Helm Deployment](./docs/module-08-helm-deployment.md) | Package and deploy `ecommerce-app` (`Deployment`, `Service`, ALB `Ingress`, and `HPA`) atomically with Helm |
| **Module 09** | [Jenkins CI/CD Pipeline](./docs/module-09-jenkins-cicd.md) | Automate checkout, Maven build, SonarQube analysis, Trivy scan, ECR push, and Helm rollout via declarative `Jenkinsfile` |
| **Module 10** | [Production Security](./docs/module-10-production-security.md) | Validate namespace security controls and store sensitive credentials (`production/db-password`) in AWS Secrets Manager |
| **Module 11** | [Monitoring and Logging](./docs/module-11-monitoring-logging.md) | Deploy Prometheus & Grafana (`kube-prometheus-stack`) and enable CloudWatch Container Insights + Fluent Bit via IRSA |
| **Module 12** | [Testing and Troubleshooting](./docs/module-12-testing-troubleshooting.md) | Run end-to-end endpoint/load checks, diagnose common EKS issues, and tear down AWS resources cleanly |

## 🧹 Recommended `.gitignore`

Before pushing changes to GitHub, ensure build artifacts, Terraform state/plans, and local secrets are excluded in `.gitignore`:

```gitignore
# Maven build output
application/ecommerce-app/target/

# Terraform cache, state, and plans
**/.terraform/
*.tfstate
*.tfstate.*
*.tfplan
tfplan
*.tfvars
!*.tfvars.example

# Secrets and private keys
.env
*.pem
*.key

# IDE files
.idea/
.vscode/
```

## ⚡ Quick Start (Git Push)

```bash
cd ~/aws-eks-project
git add README.md .gitignore docs/
git commit -m "Add complete project README and module documentation"
git push origin main
```

---

## 🙏 Thank You

Thank you for exploring the **AWS EKS E-Commerce DevOps Project**! I hope these step-by-step modules, Terraform configurations, Kubernetes manifests, Helm charts, and CI/CD pipelines serve as a helpful reference for building and operating production-ready workloads on Amazon EKS.

If you found this repository useful, feel free to star ⭐ the project, open an issue for questions or improvements, or fork it to customize for your own cloud-native architectures. Happy building!
