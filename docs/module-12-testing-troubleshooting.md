# Module 12 – Production Testing, GitHub Push & Resource Cleanup

**Region:** `ap-south-1` (Mumbai) | **Cluster:** `ecommerce-eks` | **Repository:** `r-lakshman/aws-eks-devops-project`

This module installs **Metrics Server** for live CPU/memory metrics (`kubectl top`), verifies Helm release history and cluster health, commits and pushes the completed 12-module project to GitHub, and provides a safe teardown runbook to terminate all AWS resources once your code is backed up.

## Step 1 – Install Metrics Server & Run Production Health Checks

Install Kubernetes Metrics Server (required for `kubectl top` and HPA CPU scaling) and inspect Helm history, cluster resources, and events:

```
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml || true
kubectl rollout status deployment/metrics-server -n kube-system --timeout=120s

# Check Helm release history and rollback readiness
helm history ecommerce-app -n production

# Inspect cluster nodes, workloads, autoscalers, and storage
kubectl get nodes,pods,deployments,hpa,pdb,pvc -A

# View live CPU and memory usage (wait ~60s after Metrics Server starts)
kubectl top nodes
kubectl top pods -A

# Inspect recent events in the production namespace
kubectl get events -n production --sort-by='.lastTimestamp'
```

* **Verification:** `kubectl top nodes` and `kubectl top pods -A` return live CPU/memory metrics, and `helm history ecommerce-app -n production` shows `deployed` status.

## Step 2 – Push the Completed Project to GitHub

Configure `.gitignore` so Terraform state, compiled JARs, keys, and local plans are excluded, then commit and push to `https://github.com/r-lakshman/aws-eks-devops-project.git`. *(Use a GitHub Personal Access Token with repository write permissions when prompted for `Password:`.)*

```
cd ~/aws-eks-project

cat << 'EOF' > .gitignore
.terraform/
*.tfstate
*.tfstate.*
tfplan
crash.log
target/
*.jar
*.war
*.log
*.pem
*.key
.env
*.zip
*.tar.gz
.DS_Store
EOF

git config --global user.name "r-lakshman"
git config --global user.email "your-email@example.com"

git init
git add .
git status
git commit -m "Complete 12-module AWS EKS production project" || true
git branch -M main

# Set or update the origin remote safely
git remote set-url origin https://github.com/r-lakshman/aws-eks-devops-project.git 2>/dev/null || \
  git remote add origin https://github.com/r-lakshman/aws-eks-devops-project.git

git push -u origin main
```

* **Verification:** Refresh `https://github.com/r-lakshman/aws-eks-devops-project` in your browser and confirm all folders (`terraform/`, `application/`, `kubernetes/`, `helm/`, `jenkins/`, `docs/`) and `.gitignore` are present.

## Step 3 – Terminate All AWS Resources (Cost Cleanup)

> **Warning:** Only run these commands **after** confirming your code is safely pushed to GitHub. Deleting Kubernetes Ingresses and Helm releases **before** `terraform destroy` prevents orphaned AWS Application Load Balancers (ALBs) and Security Groups from blocking VPC deletion.

### 3.1 Delete Kubernetes Workloads, Ingresses (ALBs), and Helm Releases

```
# 1. Uninstall application & monitoring Helm releases (deletes ALB Ingress & Load Balancers)
helm uninstall ecommerce-app -n production || true
helm uninstall monitoring -n monitoring || true

# 2. Delete namespaces and baseline Kubernetes policies
kubectl delete -f ~/aws-eks-project/kubernetes/ --ignore-not-found=true
kubectl delete namespace production monitoring --ignore-not-found=true

# 3. Uninstall AWS Load Balancer Controller & CloudWatch add-on
helm uninstall aws-load-balancer-controller -n kube-system || true
aws eks delete-addon --cluster-name ecommerce-eks --addon-name amazon-cloudwatch-observability --region ap-south-1 || true

# 4. Delete IRSA service accounts / IAM roles created outside Terraform
eksctl delete iamserviceaccount --cluster ecommerce-eks --region ap-south-1 --namespace kube-system --name aws-load-balancer-controller || true
eksctl delete iamserviceaccount --cluster ecommerce-eks --region ap-south-1 --namespace amazon-cloudwatch --name cloudwatch-agent || true
```

* **Verification:** Check **EC2 → Load Balancers** in `ap-south-1` (or run `aws elbv2 describe-load-balancers --region ap-south-1`) to confirm no `k8s-producti-*` ALB remains active.

### 3.2 Destroy EKS Cluster, Node Group, and VPC via Terraform

```
cd ~/aws-eks-project/terraform/environments/dev
terraform destroy -auto-approve
```

* **Verification:** `terraform destroy` finishes with `Destroy complete!`.

### 3.3 Clean Up ECR Images, Secrets Manager, CloudWatch Logs, and S3 State Bucket

```
# 1. Delete ECR repository (including all pushed images)
aws ecr delete-repository --repository-name ecommerce-app --force --region ap-south-1 || true

# 2. Delete Secrets Manager secret immediately (no recovery window)
aws secretsmanager delete-secret \
  --secret-id production/db-password \
  --force-delete-without-recovery \
  --region ap-south-1 || true

# 3. Delete leftover EKS CloudWatch log group (if present)
aws logs delete-log-group \
  --log-group-name /aws/eks/ecommerce-eks/cluster \
  --region ap-south-1 || true

# 4. Empty and delete the Terraform remote state S3 bucket (once finished with the project)
STATE_BUCKET="eks-terraform-state-846296126322-ap-south-1"
aws s3 rm "s3://${STATE_BUCKET}" --recursive || true
aws s3api delete-bucket --bucket "${STATE_BUCKET}" --region ap-south-1 || true
```

### 3.4 Terminate the Ubuntu EC2 Workstation Instance

Finally, open **AWS Console → EC2 → Instances** (`ap-south-1`), select your Ubuntu workstation instance (`i-056c9c812048051e8`), and choose **Instance state → Terminate (delete) instance** (or run `aws ec2 terminate-instances --instance-ids <INSTANCE_ID> --region ap-south-1`).

* **Verification:** Check **AWS Billing & Cost Management** and **EC2 / EKS / ELB / S3** consoles in `ap-south-1` to verify zero running billable resources remain.
