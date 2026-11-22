# Module 10 – Production Security

**Region:** `ap-south-1` (Mumbai) | **Cluster:** `ecommerce-eks` | **Namespace:** `production` | **Secret:** `production/db-password`

This module verifies that Kubernetes namespace-level security and availability controls—**ServiceAccounts**, **RBAC** (`Role` and `RoleBinding`), **NetworkPolicy**, and **PodDisruptionBudget (`PDB`)**—are active in `production`, and stores sensitive application credentials in **AWS Secrets Manager** instead of hardcoding plain-text secrets in Git or Kubernetes manifests.

## Architecture & Security Controls

| Control / Resource | Name / Identifier | Scope | Purpose | 
| ----- | ----- | ----- | ----- | 
| **RBAC** | `production-readonly` / `production-readonly-binding` | `production` namespace | Enforces least-privilege read-only access for `production-viewers` | 
| **NetworkPolicy** | `allow-app-traffic` | `production` namespace | Restricts pod ingress on `app: ecommerce-app` to TCP port `8080` | 
| **PodDisruptionBudget** | `ecommerce-pdb` | `production` namespace | Guarantees at least `1` available pod during voluntary disruptions | 
| **AWS Secrets Manager** | `production/db-password` | `ap-south-1` | Centralizes encrypted secret storage and rotation outside Git | 

## Step 1 – Verify Kubernetes Security & Availability Policies

Inspect all `ServiceAccounts`, `Roles`, `RoleBindings`, `NetworkPolicies`, and `PodDisruptionBudgets` in the `production` namespace:

```
kubectl get serviceaccounts,roles,rolebindings,networkpolicies,pdb -n production
```

* **Verification:** Output lists the `default` ServiceAccount, `role.rbac.authorization.k8s.io/production-readonly`, `rolebinding.rbac.authorization.k8s.io/production-readonly-binding`, `networkpolicy.networking.k8s.io/allow-app-traffic`, and `poddisruptionbudget.policy/ecommerce-pdb`.

## Step 2 – Ensure IAM Permissions for AWS Secrets Manager

Before creating or describing secrets from the Ubuntu EC2 workstation, confirm `ubuntu-eks-devops-role` includes Secrets Manager permissions for `arn:aws:secretsmanager:ap-south-1:<ACCOUNT_ID>:secret:production/*`:

```
{
  "Sid": "SecretsManagerForEKSProject",
  "Effect": "Allow",
  "Action": [
    "secretsmanager:CreateSecret",
    "secretsmanager:DescribeSecret",
    "secretsmanager:GetSecretValue",
    "secretsmanager:PutSecretValue",
    "secretsmanager:DeleteSecret",
    "secretsmanager:TagResource"
  ],
  "Resource": "arn:aws:secretsmanager:ap-south-1:846296126322:secret:production/*"
}
```

* **Verification:** No `AccessDeniedException` occurs when calling `aws secretsmanager` CLI commands.

## Step 3 – Store and Verify the Secret in AWS Secrets Manager

Create the `production/db-password` secret in `ap-south-1` (using `|| true` so re-runs do not fail if the secret already exists) and inspect its metadata:

```
aws secretsmanager create-secret \
  --name production/db-password \
  --secret-string 'ReplaceWithYourSecret' \
  --region ap-south-1 || true

aws secretsmanager describe-secret \
  --secret-id production/db-password \
  --region ap-south-1
```

> **Security Tip:** Replace `'ReplaceWithYourSecret'` with a strong generated password before production use, and avoid committing real secret values to Git repositories.

* **Verification:** `aws secretsmanager describe-secret` returns JSON metadata (`Name: "production/db-password"`, `ARN`, `LastChangedDate`) confirming encrypted storage in `ap-south-1`.
