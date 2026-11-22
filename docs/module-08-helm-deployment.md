# Module 8 – Helm Deployment

**Region:** `ap-south-1` (Mumbai) | **Cluster:** `ecommerce-eks` | **Namespace:** `production` | **Helm Release:** `ecommerce-app`

This module bundles the Kubernetes `Deployment`, `Service`, AWS ALB `Ingress`, and `HorizontalPodAutoscaler` (`HPA`) into a reusable Helm chart (`~/aws-eks-project/helm/ecommerce`) so application upgrades and rollbacks are versioned, atomic, and repeatable.

## Architecture & Key Parameters

| Parameter | Value | Notes | 
| ----- | ----- | ----- | 
| **Chart Directory** | `~/aws-eks-project/helm/ecommerce` | Helm v2 application chart (`ecommerce` v`0.1.0`) | 
| **Release Name** | `ecommerce-app` | Deployed into the `production` namespace | 
| **Image Repository** | `<ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/ecommerce-app` | Passed dynamically via `--set image.repository` | 
| **Replicas & Scaling** | `replicaCount: 2` (`minReplicas: 2`, `maxReplicas: 10`) | Scales at `70%` target CPU utilization | 
| **Service & Ingress** | `ClusterIP` (`80` → `8080`) + `alb` Ingress | Internet-facing ALB health-checking `/actuator/health` | 

## Step 1 – Initialize Helm Chart Directory, `Chart.yaml`, and `values.yaml`

Ensure the Helm templates directory exists and create `Chart.yaml` and `values.yaml`:

```
HELM_DIR=~/aws-eks-project/helm/ecommerce
mkdir -p "$HELM_DIR/templates"

cat << 'EOF' > "$HELM_DIR/Chart.yaml"
apiVersion: v2
name: ecommerce
description: Helm chart for ecommerce-app on EKS
type: application
version: 0.1.0
appVersion: "1.0.0"
EOF

cat << 'EOF' > "$HELM_DIR/values.yaml"
replicaCount: 2
image:
  repository: ecommerce-app
  pullPolicy: IfNotPresent
  tag: "1.0.0"
service:
  type: ClusterIP
  port: 80
  targetPort: 8080
ingress:
  enabled: true
  className: alb
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /actuator/health
resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: 500m
    memory: 1Gi
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
EOF
```

* **Verification:** `ls -lh "$HELM_DIR/Chart.yaml" "$HELM_DIR/values.yaml"` confirms both files exist.

## Step 2 – Create Helm Templates (`deployment.yaml`, `service.yaml`, `ingress.yaml`, `hpa.yaml`)

Create the four Kubernetes resource templates with valid YAML indentation:

```
cat << 'EOF' > "$HELM_DIR/templates/deployment.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}
  labels:
    app: {{ .Release.Name }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.service.targetPort }}
          livenessProbe:
            httpGet:
              path: /actuator/health
              port: {{ .Values.service.targetPort }}
            initialDelaySeconds: 30
            periodSeconds: 15
          readinessProbe:
            httpGet:
              path: /actuator/health
              port: {{ .Values.service.targetPort }}
            initialDelaySeconds: 15
            periodSeconds: 10
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
EOF

cat << 'EOF' > "$HELM_DIR/templates/service.yaml"
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}
spec:
  type: {{ .Values.service.type }}
  selector:
    app: {{ .Release.Name }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
EOF

cat << 'EOF' > "$HELM_DIR/templates/ingress.yaml"
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .Release.Name }}
  annotations:
    {{- toYaml .Values.ingress.annotations | nindent 4 }}
spec:
  ingressClassName: {{ .Values.ingress.className }}
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {{ .Release.Name }}
                port:
                  number: {{ .Values.service.port }}
{{- end }}
EOF

cat << 'EOF' > "$HELM_DIR/templates/hpa.yaml"
{{- if .Values.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ .Release.Name }}-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ .Release.Name }}
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.autoscaling.targetCPUUtilizationPercentage }}
{{- end }}
EOF
```

* **Verification:** `helm lint "$HELM_DIR"` passes with `0 chart(s) failed`.

## Step 3 – Deploy `ecommerce-app` with Helm (`--atomic`)

Resolve `ECR_REPO_URL` for your AWS account in `ap-south-1` and deploy the Helm release into `production`:

```
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO_URL="${ACCOUNT_ID}.dkr.ecr.ap-south-1.amazonaws.com/ecommerce-app"

helm upgrade --install ecommerce-app "$HELM_DIR" \
  -n production \
  --set image.repository="$ECR_REPO_URL" \
  --set image.tag="1.0.0" \
  --atomic \
  --timeout 5m
```

> **Note:** On a single `t3.small` worker node, if `2` replicas exceed available CPU/memory capacity and cause `--atomic` to roll back, pass `--set replicaCount=1 --set autoscaling.minReplicas=1` during installation.

* **Verification:** `helm upgrade --install` completes with `STATUS: deployed`.

## Step 4 – Verify Rollout, Pods, Service, ALB Ingress, and HPA

Confirm the deployment rollout completes and inspect the running resources in `production`:

```
kubectl rollout status deployment/ecommerce-app -n production
kubectl get pods,svc,ingress,hpa -n production
```

* **Verification:** `ecommerce-app` pods are `Running` (`1/1` Ready), `service/ecommerce-app` is `ClusterIP`, `ingress/ecommerce-app` receives an AWS ALB `ADDRESS` (`*.ap-south-1.elb.amazonaws.com`), and `ecommerce-app-hpa` is active.
