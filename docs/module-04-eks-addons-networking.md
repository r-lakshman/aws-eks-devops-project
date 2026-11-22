# Module 4 – EKS Add-ons and Networking

**Region:** `ap-south-1` (Mumbai) | **Cluster:** `ecommerce-eks` | **Namespace:** `kube-system`

This module sets up **IAM Roles for Service Accounts (IRSA)** via OIDC and installs the **AWS Load Balancer Controller** in `kube-system` on `ecommerce-eks` (`ap-south-1`) so Kubernetes `Ingress` resources automatically provision AWS Application Load Balancers (ALBs).

## Architecture & Key Parameters

| Parameter | Value | Notes | 
| ----- | ----- | ----- | 
| **AWS Region** | `ap-south-1` | Mumbai | 
| **Cluster Name** | `ecommerce-eks` | Existing EKS cluster | 
| **IAM Policy** | `AWSLoadBalancerControllerIAMPolicy` | Official AWS LBC permissions | 
| **IAM Role (IRSA)** | `AmazonEKSLoadBalancerControllerRole` | Assumed by controller pods via OIDC | 
| **Service Account** | `aws-load-balancer-controller` | Created in `kube-system` | 
| **Helm Release** | `aws-load-balancer-controller` | Installed from `eks/aws-load-balancer-controller` | 

## Step 1 – Resolve VPC ID and AWS Account ID

Fetch `VPC_ID` from Terraform outputs (falling back to querying the `ecommerce-eks-vpc` tag in `ap-south-1` if `vpc_id` isn't declared as a Terraform output) and retrieve your `ACCOUNT_ID`:

```
VPC_ID=$(terraform -chdir=~/aws-eks-project/terraform/environments/dev output -raw vpc_id 2>/dev/null || \
  aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=ecommerce-eks-vpc" \
    --region ap-south-1 \
    --query "Vpcs[0].VpcId" \
    --output text)

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "VPC_ID=${VPC_ID} | ACCOUNT_ID=${ACCOUNT_ID}"
```

* **Verification:** Both `VPC_ID` (`vpc-...`) and `ACCOUNT_ID` print non-empty values without errors.

## Step 2 – Associate IAM OIDC Provider and Create IAM Policy

Associate the cluster's IAM OIDC provider, download the AWS Load Balancer Controller IAM policy document, and create the policy if it does not already exist:

```
eksctl utils associate-iam-oidc-provider \
  --cluster ecommerce-eks \
  --region ap-south-1 \
  --approve

curl -sSL -o /tmp/alb-iam-policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file:///tmp/alb-iam-policy.json || true
```

* **Verification:** The OIDC provider is associated with `ecommerce-eks` and `AWSLoadBalancerControllerIAMPolicy` exists in IAM (`EntityAlreadyExists` is safely ignored if already created).

## Step 3 – Create the IRSA Role and Kubernetes Service Account

### Option A: Using `eksctl` (Requires CloudFormation Stack Permissions)

```
eksctl create iamserviceaccount \
  --cluster ecommerce-eks \
  --region ap-south-1 \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy" \
  --approve
```

### Option B: Using AWS CLI + `kubectl` Directly (No CloudFormation Required)

If `ubuntu-eks-devops-role` does not allow `cloudformation:CreateStack`, create the IAM role and annotated Kubernetes ServiceAccount directly:

```
OIDC_ISSUER=$(aws eks describe-cluster \
  --name ecommerce-eks \
  --region ap-south-1 \
  --query "cluster.identity.oidc.issuer" \
  --output text)
OIDC_HOSTPATH=${OIDC_ISSUER#https://}

cat << EOF > /tmp/alb-trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_HOSTPATH}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_HOSTPATH}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller",
          "${OIDC_HOSTPATH}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --assume-role-policy-document file:///tmp/alb-trust-policy.json || true

aws iam attach-role-policy \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy"

kubectl create serviceaccount aws-load-balancer-controller \
  -n kube-system \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl annotate serviceaccount aws-load-balancer-controller \
  -n kube-system \
  "eks.amazonaws.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/AmazonEKSLoadBalancerControllerRole" \
  --overwrite
```

Verify the ServiceAccount annotation:

```
kubectl get sa aws-load-balancer-controller -n kube-system -o yaml
```

* **Verification:** `kubectl get sa` displays the `eks.amazonaws.com/role-arn` annotation pointing to `arn:aws:iam::<ACCOUNT_ID>:role/AmazonEKSLoadBalancerControllerRole`.

## Step 4 – Install AWS Load Balancer Controller via Helm

Add the `eks` Helm chart repository, update it, and install/upgrade `aws-load-balancer-controller` in `kube-system` using the existing annotated service account *(add `--set replicaCount=1` if your `t3.small` worker node is tight on memory)*:

```
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=ecommerce-eks \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=ap-south-1 \
  --set vpcId="$VPC_ID"
```

* **Verification:** `helm upgrade --install` reports `STATUS: deployed`.

## Step 5 – Verify Controller Deployment and Pods

Check the deployment rollout status and pods in `kube-system`:

```
kubectl get deployment aws-load-balancer-controller -n kube-system
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=180s
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller -o wide
```

* **Verification:** The deployment reaches `AVAILABLE` (e.g., `2/2` or `1/1`) and `aws-load-balancer-controller` pods show `Running`.
