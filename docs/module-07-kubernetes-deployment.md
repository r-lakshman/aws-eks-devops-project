# Module 7 – Kubernetes Deployment

**Region:** `ap-south-1` (Mumbai) | **Cluster:** `ecommerce-eks` | **Namespace:** `production`

This module creates the `production` namespace and applies baseline Kubernetes operational and security policies—**RBAC** (`Role` and `RoleBinding`), **NetworkPolicy**, and **PodDisruptionBudget (PDB)**—before deploying the application workload.

## Architecture & Key Parameters

| Resource | Name | Namespace | Purpose | 
| ----- | ----- | ----- | ----- | 
| **Namespace** | `production` | Cluster-wide | Isolates production application workloads and policies | 
| **Role & RoleBinding** | `production-readonly` | `production` | Grants read-only (`get`, `list`, `watch`) access to `production-viewers` | 
| **NetworkPolicy** | `allow-app-traffic` | `production` | Restricts ingress on `app: ecommerce-app` pods to TCP port `8080` | 
| **PodDisruptionBudget** | `ecommerce-pdb` | `production` | Ensures `minAvailable: 1` pod during voluntary node disruptions | 

## Step 1 – Create the `production` Namespace

Ensure your `~/aws-eks-project/kubernetes` directory exists and idempotently create the `production` namespace:

```
mkdir -p ~/aws-eks-project/kubernetes

kubectl create namespace production --dry-run=client -o yaml | kubectl apply -f -
```

* **Verification:** `kubectl get namespace production` shows `production` with status `Active`.

## Step 2 – Create RBAC Manifest (`rbac.yaml`)

Define a namespace-scoped read-only `Role` (`production-readonly`) for `pods`, `services`, and `configmaps`, and bind it to the `production-viewers` group:

```
cat << 'EOF' > ~/aws-eks-project/kubernetes/rbac.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: production-readonly
  namespace: production
rules:
  - apiGroups: [""]
    resources: ["pods", "services", "configmaps"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: production-readonly-binding
  namespace: production
subjects:
  - kind: Group
    name: production-viewers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: production-readonly
  apiGroup: rbac.authorization.k8s.io
EOF
```

* **Verification:** `cat ~/aws-eks-project/kubernetes/rbac.yaml` displays valid YAML for both `Role` and `RoleBinding`.

## Step 3 – Create NetworkPolicy Manifest (`network-policy.yaml`)

Restrict ingress traffic reaching pods labeled `app: ecommerce-app` to TCP port `8080` *(note that enforcement requires a CNI network policy engine such as AWS VPC CNI Network Policy or Calico)*:

```
cat << 'EOF' > ~/aws-eks-project/kubernetes/network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-app-traffic
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: ecommerce-app
  policyTypes:
    - Ingress
  ingress:
    - ports:
        - protocol: TCP
          port: 8080
EOF
```

* **Verification:** `cat ~/aws-eks-project/kubernetes/network-policy.yaml` displays properly indented YAML targeting port `8080`.

## Step 4 – Create PodDisruptionBudget Manifest (`pdb.yaml`)

Ensure at least `1` replica of `ecommerce-app` remains available during voluntary node drains or cluster upgrades:

```
cat << 'EOF' > ~/aws-eks-project/kubernetes/pdb.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: ecommerce-pdb
  namespace: production
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: ecommerce-app
EOF
```

* **Verification:** `cat ~/aws-eks-project/kubernetes/pdb.yaml` confirms `minAvailable: 1` and `matchLabels.app: ecommerce-app`.

## Step 5 – Apply and Verify All Kubernetes Baseline Policies

Apply all manifests under `~/aws-eks-project/kubernetes/` and inspect the created resources in `production`:

```
kubectl apply -f ~/aws-eks-project/kubernetes/

kubectl get roles,rolebindings,networkpolicies,pdb -n production
```

* **Verification:** `kubectl apply` reports `created` or `configured` for `production-readonly`, `production-readonly-binding`, `allow-app-traffic`, and `ecommerce-pdb`, and `kubectl get` lists all four resources in `production`.
