# Module 11 – Monitoring and Logging

**Region:** `ap-south-1` (Mumbai) | **Cluster:** `ecommerce-eks` | **Namespaces:** `monitoring`, `amazon-cloudwatch`

This module deploys **Prometheus** and **Grafana** (`kube-prometheus-stack`) for cluster and application metrics, and enables **AWS CloudWatch Container Insights + Fluent Bit** via the `amazon-cloudwatch-observability` EKS add-on with IRSA for centralized log aggregation.

## Architecture & Key Parameters

| Component | Namespace | Helm / Add-on Identifier | Purpose | 
| ----- | ----- | ----- | ----- | 
| **Prometheus & Grafana** | `monitoring` | `prometheus-community/kube-prometheus-stack` | Scrapes cluster/pod metrics and provides Grafana dashboards | 
| **IRSA Role & SA** | `amazon-cloudwatch` | `EKSCloudWatchAgentRole` / `cloudwatch-agent` | Grants pods `CloudWatchAgentServerPolicy` permissions via OIDC | 
| **CloudWatch Observability** | `amazon-cloudwatch` | `amazon-cloudwatch-observability` (EKS Add-on) | Collects Container Insights metrics and streams pod logs via Fluent Bit | 

## Step 1 – Deploy Prometheus and Grafana (`kube-prometheus-stack`)

Add the `prometheus-community` Helm repository, update charts, create the `monitoring` namespace, and install `kube-prometheus-stack`:

```
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring
```

> **Note:** On a single `t3.small` worker node, `kube-prometheus-stack` deploys multiple components (Prometheus, Grafana, Alertmanager, kube-state-metrics, node-exporter). If pods remain `Pending` due to CPU/memory limits, scale up your node group or reduce resource requests via Helm values.

* **Verification:** `helm status monitoring -n monitoring` shows `STATUS: deployed`.

## Step 2 – Create the IRSA Role for CloudWatch Observability

Resolve your `ACCOUNT_ID` and configure `EKSCloudWatchAgentRole` with `CloudWatchAgentServerPolicy` for `amazon-cloudwatch/cloudwatch-agent`.

### Option A: Using `eksctl` (Requires CloudFormation Stack Permissions)

```
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

eksctl create iamserviceaccount \
  --cluster ecommerce-eks \
  --region ap-south-1 \
  --namespace amazon-cloudwatch \
  --name cloudwatch-agent \
  --role-name EKSCloudWatchAgentRole \
  --attach-policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy \
  --approve
```

### Option B: Using AWS CLI + `kubectl` Directly (No CloudFormation Required)

If `ubuntu-eks-devops-role` does not allow `cloudformation:CreateStack`, create the IAM role and ServiceAccount directly:

```
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OIDC_ISSUER=$(aws eks describe-cluster \
  --name ecommerce-eks \
  --region ap-south-1 \
  --query "cluster.identity.oidc.issuer" \
  --output text)
OIDC_HOSTPATH=${OIDC_ISSUER#https://}

cat << EOF > /tmp/cw-trust-policy.json
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
          "${OIDC_HOSTPATH}:sub": "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent",
          "${OIDC_HOSTPATH}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name EKSCloudWatchAgentRole \
  --assume-role-policy-document file:///tmp/cw-trust-policy.json || true

aws iam attach-role-policy \
  --role-name EKSCloudWatchAgentRole \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy

kubectl create namespace amazon-cloudwatch --dry-run=client -o yaml | kubectl apply -f -

kubectl create serviceaccount cloudwatch-agent \
  -n amazon-cloudwatch \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl annotate serviceaccount cloudwatch-agent \
  -n amazon-cloudwatch \
  "eks.amazonaws.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/EKSCloudWatchAgentRole" \
  --overwrite

```

* **Verification:** `aws iam get-role --role-name EKSCloudWatchAgentRole` returns the IAM role details and `kubectl get sa cloudwatch-agent -n amazon-cloudwatch -o yaml` shows the `eks.amazonaws.com/role-arn` annotation.

## Step 3 – Enable the `amazon-cloudwatch-observability` EKS Add-on

Install the managed CloudWatch Observability add-on on `ecommerce-eks` using the IRSA role created above:

```
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws eks create-addon \
  --cluster-name ecommerce-eks \
  --addon-name amazon-cloudwatch-observability \
  --service-account-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/EKSCloudWatchAgentRole" \
  --region ap-south-1
```

* **Verification:** `aws eks describe-addon --cluster-name ecommerce-eks --addon-name amazon-cloudwatch-observability --region ap-south-1` transitions from `CREATING` to `ACTIVE`.

## Step 4 – Verify Monitoring and Logging Pods

Check that Prometheus, Grafana, the CloudWatch agent, and Fluent Bit DaemonSet pods are running:

```
kubectl get pods -n monitoring
kubectl get pods -n amazon-cloudwatch
```

* **Verification:** Pods in both `monitoring` (Prometheus, Grafana, node-exporter, kube-state-metrics) and `amazon-cloudwatch` (`cloudwatch-agent`, `fluent-bit`) show `Running` status, and container logs appear under `/aws/containerinsights/ecommerce-eks/application` in AWS CloudWatch Logs.
