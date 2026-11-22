# MODULE 3 – AWS EKS CLUSTER CREATION

**Cluster Provisioning, Managed Node Group Setup, and Troubleshooting Runbook**

* **Region:** `ap-south-1` (Mumbai)
* **Cluster Name:** `ecommerce-eks`
* **Worker Instance Type:** `t3.small`
* **Workstation:** Ubuntu EC2 (`~/aws-eks-project/terraform/environments/dev`)

This module provisions and verifies the `ecommerce-eks` control plane and `application` managed node group (`t3.small`) using Terraform, incorporating resolutions for IAM policy warnings, S3 state locks, stale plans, CloudWatch log group conflicts, `NodeCreationFailure`, and core add-on (`vpc-cni`, `kube-proxy`, `coredns`) readiness.

---

## 1. Navigate to the Terraform Project

```bash
cd ~/aws-eks-project/terraform/environments/dev
ls -lh
```

Expected files:

```text
terraform.tf
providers.tf
variables.tf
vpc.tf
eks.tf
```

---

## 2. Configure IAM Permissions for `ubuntu-eks-devops-role`

To avoid `AccessDenied`, duplicate `Sid`, and `Create SLR With Star In Resource` warnings during EKS creation:

1. Open **AWS Console → IAM → Policies**, select the policy attached to `ubuntu-eks-devops-role`, and click **Edit**.
2. Ensure every statement has a **unique `Sid`** (AWS IAM rejects duplicate `Sid` values).
3. Scope `iam:CreateServiceLinkedRole` to the EKS service-linked role ARN rather than `*`:

```json
{
  "Sid": "CreateEKSServiceLinkedRole",
  "Effect": "Allow",
  "Action": "iam:CreateServiceLinkedRole",
  "Resource": "arn:aws:iam::*:role/aws-service-role/eks.amazonaws.com/AWSServiceRoleForAmazonEKS*"
}
```

4. Ensure discovery and lifecycle actions include `kms:ListAliases`, `iam:GetOpenIDConnectProvider`, `iam:ListOpenIDConnectProviders`, `iam:GetInstanceProfile`, and `autoscaling:*`, then click **Next → Save changes**.

Verify your active caller identity:

```bash
aws sts get-caller-identity
```

---

## 3. Configure EKS Cluster & Worker Nodes in `eks.tf`

Open `eks.tf`:

```bash
nano eks.tf
```

Ensure the `ecommerce-eks` cluster uses your public subnets (since no NAT Gateway is provisioned in Module 2) and configure the `application` managed node group with `t3.small` and `1` worker node:

| Configuration | Value |
| --- | --- |
| **Cluster name** | `ecommerce-eks` |
| **Node group name** | `application` (`application-nodes`) |
| **Instance type** | `t3.small` |
| **Minimum nodes** | `1` |
| **Maximum nodes** | `1` |
| **Desired nodes** | `1` |
| **Subnets** | Public subnets (`aws_subnet.public[*].id`) |
| **Region** | `ap-south-1` |

```hcl
eks_managed_node_groups = {
  application = {
    name           = "application-nodes"
    instance_types = ["t3.small"]
    subnet_ids     = aws_subnet.public[*].id

    min_size     = 1
    max_size     = 1
    desired_size = 1
  }
}
```

> **Important:** Preserve your existing module structure and other settings. Do not blindly replace the entire file. Save with `Ctrl + O`, `Enter`, and `Ctrl + X`.

Verify configuration:

```bash
grep -n "cluster_name\|instance_types" eks.tf
grep -n -C 3 "desired_size\|min_size\|max_size" eks.tf
```

---

## 4. Check Existing EKS Cluster & Node Groups

### 4.1 Verify Cluster via AWS Console or CLI

In **AWS Console → EKS → Clusters → `ecommerce-eks`** (`ap-south-1`), or via CLI:

```bash
aws eks describe-cluster \
  --name ecommerce-eks \
  --region ap-south-1 \
  --query 'cluster.{Name:name,Status:status,Version:version,Endpoint:endpoint}' \
  --output table
```

*(If `ecommerce-eks` is already `ACTIVE`, do not recreate it.)*

### 4.2 Inspect Existing or Failed Node Groups

```bash
aws eks list-nodegroups \
  --cluster-name ecommerce-eks \
  --region ap-south-1

for NG in $(aws eks list-nodegroups \
  --cluster-name ecommerce-eks \
  --region ap-south-1 \
  --query 'nodegroups[]' \
  --output text); do

  echo "NODE GROUP: $NG"

  aws eks describe-nodegroup \
    --cluster-name ecommerce-eks \
    --nodegroup-name "$NG" \
    --region ap-south-1 \
    --query 'nodegroup.{Status:status,Issues:health.issues,Scaling:scalingConfig,NodeRole:nodeRole}' \
    --output json

done
```

Check for:

* **`ACTIVE`** – Node group successfully created.
* **`CREATE_FAILED`** – Inspect `Issues` (such as `NodeCreationFailure`), verify subnet internet routing, node IAM policies, and Auto Scaling activities (`aws autoscaling describe-scaling-activities`).
* **`CREATING`** – Node group creation is still in progress.

> **Important:** Do not manually delete failed node groups before checking Terraform state and determining whether Terraform manages them.

---

## 5. Verify Terraform State Lock & Clean Stale Plan Files

```bash
ps aux | grep '[t]erraform'
rm -f tfplan
terraform state list
```

Only if no Terraform operation is running and Terraform reports a stale state lock ID:

```bash
terraform force-unlock 6e9379b0-13e0-97b8-423c-cfef0739d8d0
```

*(Use the actual lock ID reported by Terraform if it differs.)*

---

## 6. Check CloudWatch Log Group

Check whether `/aws/eks/ecommerce-eks/cluster` already exists in `ap-south-1` or is tracked in Terraform state:

```bash
aws logs describe-log-groups \
  --log-group-name-prefix /aws/eks/ecommerce-eks/cluster \
  --region ap-south-1

terraform state list | grep cloudwatch
```

* **Import if keeping existing logs:**
  ```bash
  terraform import \
    'module.eks.aws_cloudwatch_log_group.this[0]' \
    /aws/eks/ecommerce-eks/cluster
  ```
* **Or delete if left over from a failed cluster creation attempt and you want Terraform to recreate it:**
  ```bash
  aws logs delete-log-group \
    --log-group-name /aws/eks/ecommerce-eks/cluster \
    --region ap-south-1
  ```

---

## 7. Format, Validate, Plan, and Apply Terraform

```bash
terraform fmt -recursive
terraform validate

terraform plan -out=tfplan
terraform show tfplan

terraform apply tfplan
```

> **Important:** Always generate a saved plan using `terraform plan -out=tfplan` (never pass a saved plan file as a positional argument to `terraform plan`), and do not proceed if Terraform unexpectedly plans to destroy your VPC or EKS cluster.

---

## 8. Verify EKS Cluster, Node Group, and EC2 Worker Instance

### 8.1 Verify EKS Cluster Status

```bash
aws eks describe-cluster \
  --name ecommerce-eks \
  --region ap-south-1 \
  --query 'cluster.{Name:name,Status:status,Version:version,Endpoint:endpoint}' \
  --output table
```

### 8.2 Verify Managed Node Group Status

```bash
for NG in $(aws eks list-nodegroups \
  --cluster-name ecommerce-eks \
  --region ap-south-1 \
  --query 'nodegroups[]' \
  --output text); do

  echo "NODE GROUP: $NG"

  aws eks describe-nodegroup \
    --cluster-name ecommerce-eks \
    --nodegroup-name "$NG" \
    --region ap-south-1 \
    --query 'nodegroup.{Status:status,Issues:health.issues,Desired:scalingConfig.desiredSize,InstanceTypes:instanceTypes}' \
    --output json

done
```

Expected output:

```json
{
  "Status": "ACTIVE",
  "Issues": [],
  "Desired": 1,
  "InstanceTypes": [
    "t3.small"
  ]
}
```

### 8.3 Verify EC2 Worker Instance

```bash
aws ec2 describe-instances \
  --region ap-south-1 \
  --filters \
    "Name=instance-type,Values=t3.small" \
    "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].{ID:InstanceId,Type:InstanceType,State:State.Name,PrivateIP:PrivateIpAddress}' \
  --output table
```

*(This lists all matching running `t3.small` instances in `ap-south-1`, not exclusively EKS instances.)*

---

## 9. Connect `kubectl`, Install Core Add-Ons, and Fix `DEGRADED` Add-Ons

### 9.1 Update `kubeconfig` and Check Cluster Connection

```bash
aws eks update-kubeconfig \
  --region ap-south-1 \
  --name ecommerce-eks

kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A
```

### 9.2 Install Core Add-Ons If Missing (`NotReady` / `cni plugin not initialized`)

If `aws eks list-addons` is empty or worker nodes show `NotReady` with `cni plugin not initialized` and no `kube-system` pods, install `vpc-cni`, `kube-proxy`, and `coredns`:

```bash
aws eks list-addons --cluster-name ecommerce-eks --region ap-south-1

aws eks create-addon --cluster-name ecommerce-eks --addon-name vpc-cni --region ap-south-1
aws eks create-addon --cluster-name ecommerce-eks --addon-name kube-proxy --region ap-south-1
aws eks create-addon --cluster-name ecommerce-eks --addon-name coredns --region ap-south-1
```

### 9.3 Check Add-On Status & Remediate `DEGRADED` Add-Ons (e.g., `coredns`)

```bash
for ADDON in vpc-cni kube-proxy coredns; do
  echo "ADDON: $ADDON"
  aws eks describe-addon \
    --cluster-name ecommerce-eks \
    --addon-name "$ADDON" \
    --region ap-south-1 \
    --query 'addon.{Status:status,Version:addonVersion,Health:health}' \
    --output json
done
```

If `coredns` (or another add-on) reports `DEGRADED` after nodes become `Ready`:

```bash
kubectl get pods -n kube-system -o wide
kubectl describe pods -n kube-system -l k8s-app=kube-dns

aws eks update-addon \
  --cluster-name ecommerce-eks \
  --addon-name coredns \
  --resolve-conflicts OVERWRITE \
  --region ap-south-1

kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system --timeout=120s
```

* **Verification:** `kubectl get nodes -o wide` shows the worker node as `Ready`, `kube-system` pods (`aws-node`, `kube-proxy`, `coredns`) are `Running`, and all three add-ons report `ACTIVE`.

---

## 10. Terraform State Verification

```bash
cd ~/aws-eks-project/terraform/environments/dev
terraform state list
```

Expected key resources include:

```text
module.eks.aws_eks_cluster.this[0]
module.eks.aws_iam_role.this[0]
module.eks.aws_iam_openid_connect_provider.oidc_provider[0]
module.eks.module.eks_managed_node_group["application"].aws_eks_node_group.this[0]
```

**Module 3 Status:** `ecommerce-eks` cluster, `t3.small` worker node group, and core Kubernetes add-ons are provisioned and verified.
