# 🚀 Complete Step-by-Step Spring Boot EKS Deployment Flow with Diagrams

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Pre-Deployment Checklist](#pre-deployment-checklist)
3. [Step-by-Step Deployment Flow](#step-by-step-deployment-flow)
4. [Verification at Each Step](#verification-at-each-step)
5. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

### High-Level System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          INTERNET                                │
│                       Users/Clients                              │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │ HTTPS requests
                             ↓
          ┌──────────────────────────────────────┐
          │    AWS Load Balancer (NLB)           │
          │  (Auto-created by ingress-nginx)     │
          │  DNS: k8s-ingressn-7ddea...elb.aws  │
          └────────┬──────────────────────────────┘
                   │
                   │ Routes to NGINX controller
                   ↓
    ┌──────────────────────────────────────────────┐
    │         EKS Cluster (ap-south-1)             │
    │                                              │
    │  ┌────────────────────────────────────────┐  │
    │  │      NGINX Ingress Controller (Pod)   │  │
    │  │  • Routes traffic based on hostname   │  │
    │  │  • Terminates SSL/TLS                 │  │
    │  │  • Applies rewrite rules              │  │
    │  └───────────┬──────────────────────────┘  │
    │             │                              │
    │             │ Routes to service            │
    │             ↓                              │
    │  ┌─────────────────────────────────��──────┐  │
    │  │    Spring Boot Service (ClusterIP)    │  │
    │  │  • Internal DNS: spring-boot-...     │  │
    │  │  • Exposes port 8080 to pods         │  │
    │  └───────────┬──────────────────────────┘  │
    │             │                              │
    │             │ Selects pods with label:    │
    │             │ app=spring-boot-kubernetes  │
    │             ↓                              │
    │  ┌────────────────────────────────────────┐  │
    │  │  Spring Boot Pods (2+ replicas)       │  │
    │  │  • Java 21 application                │  │
    │  │  • Listening on port 8080             │  │
    │  │  • Connected to RDS PostgreSQL        │  │
    │  │  • Health check: /actuator/health     │  │
    │  └────────────────────────────────────────┘  │
    │                                              │
    └──────────────────────────────────────────────┘
                   │
                   │ TCP port 5432
                   ↓
    ┌──────────────────────────────────────────────┐
    │    AWS RDS PostgreSQL                        │
    │    (Managed Database)                        │
    │    • Automated backups                       │
    │    • Multi-AZ failover                       │
    │    • Encryption at rest                      │
    └──────────────────────────────────────────────┘
```

### Deployment Flow (High Level)

```
START
  │
  ├─ Step 1: Setup AWS Infrastructure
  │   ├─ Create VPC with subnets
  │   ├─ Create RDS PostgreSQL instance
  │   └─ Create EKS cluster with node groups
  │
  ├─ Step 2: Build Docker Image
  │   ├─ Java code → Maven build
  │   ├─ Package as Docker image
  │   └─ Push to AWS ECR
  │
  ├─ Step 3: Install Kubernetes Controllers
  │   ├─ Install NGINX Ingress Controller
  │   ├─ Install Cert-Manager (for SSL)
  │   └─ Install Argo CD (GitOps)
  │
  ├─ Step 4: Create Kubernetes Manifests
  │   ├─ Deployment (Spring Boot pod definition)
  │   ├─ Service (internal service)
  │   ├─ Ingress (expose via HTTP/HTTPS)
  │   ├─ ClusterIssuer (SSL certificate)
  │   └─ ConfigMaps & Secrets (config & credentials)
  │
  ├─ Step 5: Deploy to EKS
  │   ├─ Apply Kubernetes manifests
  │   ├─ Wait for pods to be ready
  │   └─ Verify health checks
  │
  ├─ Step 6: Configure DNS & SSL
  │   ├─ Get Load Balancer DNS
  │   ├─ Point domain via CNAME
  │   ├─ Wait for certificate issuance
  │   └─ Verify HTTPS works
  │
  └─ END: Application Live! 🚀
```

---

## Pre-Deployment Checklist

Before you start, verify:

```
Infrastructure Requirements:
☑ AWS Account with sufficient quota
☑ VPC with public and private subnets
☑ RDS PostgreSQL instance running
☑ EKS cluster created (1.27+)
☑ Node groups with proper tags

Tools Installed Locally:
☑ AWS CLI (v2+)
☑ kubectl (matches cluster version)
☑ Helm 3
☑ Docker (for image building)
☑ Git (for code management)

Code Ready:
☑ Spring Boot application code
☑ Dockerfile in repo root
☑ Database migrations (Flyway)
☑ application.properties configured
☑ Docker image pushed to ECR

Team Access:
☑ AWS IAM credentials configured
☑ kubectl context configured
☑ GitHub access (for pushing code)
☑ ECR access (for pushing images)
☑ Domain registrar access (for DNS)
```

---

## Step-by-Step Deployment Flow

---

## **PHASE 1: INFRASTRUCTURE SETUP** (1-2 hours)

### Step 1: Create/Verify AWS Infrastructure

#### 1.1 Verify VPC Exists

```bash
# List VPCs
aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,Tags[?Key==`Name`].Value[0]]' --output table

# Expected output:
# VpcId              Name
# vpc-1a2b3c4d       eks-vpc
```

#### 1.2 Verify Subnets (Public & Private)

```bash
VPC_ID="vpc-1a2b3c4d"

# List subnets
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[*].[SubnetId,CidrBlock,Tags[?Key==`Name`].Value[0],Tags[?Key==`kubernetes.io/role/elb`].Value[0]]' \
  --output table

# Expected: Mix of public subnets (with IGW) and private subnets
```

**Diagram: VPC Structure**

```
VPC: 10.0.0.0/16
│
├─ Public Subnet A (10.0.1.0/24)
│  ├─ Route: 0.0.0.0/0 → Internet Gateway
│  └─ Instances: NAT Gateway
│
├─ Public Subnet B (10.0.2.0/24)
│  ├─ Route: 0.0.0.0/0 → Internet Gateway
│  └─ Instances: (empty)
│
├─ Private Subnet A (10.0.11.0/24)
│  ├─ Route: 0.0.0.0/0 → NAT Gateway
│  └─ EKS Nodes will run here
│
└─ Private Subnet B (10.0.12.0/24)
   ├─ Route: 0.0.0.0/0 → NAT Gateway
   └─ RDS DB will run here
```

#### 1.3 Verify RDS Database

```bash
# Check RDS instance
aws rds describe-db-instances \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus,Engine]' \
  --output table

# Expected output:
# DBInstanceIdentifier     Status    Engine
# spring-boot-db           available postgres

# Get connection details
DB_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier spring-boot-db \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

echo "DB Host: $DB_ENDPOINT"
echo "DB Port: 5432"
echo "DB Name: mydb"
```

#### 1.4 Verify EKS Cluster

```bash
CLUSTER_NAME="spring-boot-eks-cluster"

# Check cluster status
aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --query 'cluster.[Name,Status,Version]' \
  --output table

# Expected: Status = ACTIVE

# Configure kubectl
aws eks update-kubeconfig --name $CLUSTER_NAME --region ap-south-1

# Test kubectl access
kubectl cluster-info
kubectl get nodes

# Expected: At least 2 nodes in Ready state
```

**Diagram: EKS Cluster Structure**

```
EKS Cluster
│
├─ Control Plane (Managed by AWS)
│  ├─ API Server
│  ├─ etcd
│  └─ Scheduler
│
├─ Node Group 1 (ap-south-1a)
│  ├─ t3.medium Instance
│  ├─ Kubelet
│  └─ Container Runtime (containerd)
│
├─ Node Group 2 (ap-south-1b)
│  ├─ t3.medium Instance
│  ├─ Kubelet
│  └─ Container Runtime (containerd)
│
└─ Add-ons
   ├─ CNI (Networking)
   ├─ CoreDNS (Service discovery)
   └─ kube-proxy (Service routing)
```

---

## **PHASE 2: DOCKER IMAGE BUILD & PUSH** (15-30 mins)

### Step 2: Build and Push Docker Image to ECR

#### 2.1 Create ECR Repository

```bash
REPOSITORY_NAME="spring-boot-kubernetes"
REGION="ap-south-1"

# Create ECR repo
aws ecr create-repository \
  --repository-name $REPOSITORY_NAME \
  --region $REGION

# Get ECR URI
ECR_URI=$(aws ecr describe-repositories \
  --repository-names $REPOSITORY_NAME \
  --region $REGION \
  --query 'repositories[0].repositoryUri' \
  --output text)

echo "ECR Repository: $ECR_URI"
# Example: 123456789012.dkr.ecr.ap-south-1.amazonaws.com/spring-boot-kubernetes
```

**Diagram: ECR Structure**

```
AWS Account
│
└─ ECR (Elastic Container Registry)
   │
   └─ Repository: spring-boot-kubernetes
      │
      ├─ Image Tag: v1.0.0
      │  ├─ Layer 1: Base Java image
      │  ├─ Layer 2: Application JAR
      │  └─ Digest: sha256:abc123...
      │
      ├─ Image Tag: v1.0.1
      │  └─ ...
      │
      └─ Image Tag: latest
         └─ Points to latest build
```

#### 2.2 Build Docker Image

```bash
# Navigate to project root (where Dockerfile is)
cd spring-boot-kubernetes

# Build image
docker build -t $REPOSITORY_NAME:latest \
  -t $REPOSITORY_NAME:v1.0.0 \
  --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
  --build-arg VERSION=1.0.0 \
  .

# Verify image
docker images | grep spring-boot-kubernetes
```

#### 2.3 Login to ECR and Push

```bash
# Get login token
aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin $ECR_URI

# Tag image with ECR URI
docker tag $REPOSITORY_NAME:latest $ECR_URI:latest
docker tag $REPOSITORY_NAME:v1.0.0 $ECR_URI:v1.0.0

# Push to ECR
docker push $ECR_URI:latest
docker push $ECR_URI:v1.0.0

# Verify in ECR
aws ecr describe-images \
  --repository-name $REPOSITORY_NAME \
  --query 'imageDetails[*].[imageTags,imageSizeInBytes]' \
  --output table
```

**Diagram: Docker Build & Push Flow**

```
Local Machine
│
├─ Source Code (Git)
│  ├─ Java files
│  ├─ Application Properties
│  ├─ Dockerfile
│  └─ pom.xml
│
├─ Docker Build
│  ├─ 1. FROM openjdk:21-jdk
│  ├─ 2. COPY source code
│  ├─ 3. RUN maven build
│  ├─ 4. COPY JAR to image
│  └─ 5. Create image (150MB)
│
└─ Docker Push to ECR
   │
   └─ AWS ECR
      └─ spring-boot-kubernetes:v1.0.0
         ├─ Layer 1: openjdk:21 (500MB)
         ├─ Layer 2: Application (50MB)
         └─ Digest: sha256:abc123...
```

---

## **PHASE 3: KUBERNETES CONTROLLERS INSTALLATION** (30-45 mins)

### Step 3: Install NGINX Ingress Controller

#### 3.1 Add Helm Repository

```bash
# Add NGINX Ingress Helm repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Search for chart
helm search repo ingress-nginx/ingress-nginx
```

#### 3.2 Create values file

```bash
# Create values-nginx.yaml
cat > values-nginx.yaml <<'EOF'
controller:
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
      service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
      service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "tcp"
  
  resources:
    requests:
      cpu: 100m
      memory: 90Mi
    limits:
      cpu: 500m
      memory: 512Mi

  replicaCount: 2
  
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: app.kubernetes.io/name
              operator: In
              values:
              - ingress-nginx
          topologyKey: kubernetes.io/hostname
EOF
```

#### 3.3 Install NGINX Ingress Controller

```bash
# Create ingress-nginx namespace
kubectl create namespace ingress-nginx

# Install using Helm
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --values values-nginx.yaml \
  --wait

# Verify installation
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx

# Wait for EXTERNAL-IP assignment (may take 2-3 minutes)
watch 'kubectl get svc -n ingress-nginx ingress-nginx-controller'
```

**Expected Output:**
```
NAME                              TYPE           CLUSTER-IP       EXTERNAL-IP
ingress-nginx-controller          LoadBalancer   10.100.50.123    k8s-ingressn-7ddea...ap-south-1.elb.amazonaws.com
```

**Diagram: NGINX Controller Architecture**

```
NGINX Ingress Controller Pod
│
├─ NGINX Process
│  ├─ Listen on port 80 (HTTP)
│  ├─ Listen on port 443 (HTTPS)
│  ├─ Load config from K8s API
│  └─ Route traffic based on hostname/path
│
├─ Controller Sidecar
│  ├─ Watch Ingress resources
│  ├─ Watch Service resources
│  └─ Reload NGINX on changes
│
└─ Service (Type: LoadBalancer)
   ├─ AWS creates NLB automatically
   ├─ Assigns AWS DNS name
   └─ Maps port 80 → pod:8080, port 443 → pod:8443
```

### Step 4: Install Cert-Manager (for SSL/TLS)

#### 4.1 Install Cert-Manager

```bash
# Add Jetstack Helm repo
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Create namespace
kubectl create namespace cert-manager

# Install Cert-Manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set installCRDs=true \
  --wait

# Verify installation
kubectl get pods -n cert-manager
```

#### 4.2 Create ClusterIssuer for Let's Encrypt

```bash
cat > clusterissuer.yaml <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: your-email@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

# Apply ClusterIssuer
kubectl apply -f clusterissuer.yaml

# Verify
kubectl get clusterissuer
```

**Diagram: Cert-Manager Flow**

```
ClusterIssuer (letsencrypt-prod)
│
└─ When Ingress with cert annotation is created:
   │
   ├─ 1. Cert-Manager detects Ingress
   ├─ 2. Creates Certificate resource
   ├─ 3. Initiates ACME challenge (Let's Encrypt)
   ├─ 4. NGINX serves challenge response
   ├─ 5. Let's Encrypt validates ownership
   ├─ 6. Certificate issued
   ├─ 7. Stored in K8s Secret
   └─ 8. NGINX loads certificate for HTTPS
```

### Step 5: Install Argo CD (GitOps)

#### 5.1 Install Argo CD

```bash
# Create namespace
kubectl create namespace argocd

# Install Argo CD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for pods
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Get initial admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "Argo CD Admin Password: $ARGOCD_PASSWORD"

# Port-forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
```

#### 5.2 Connect Git Repository

```bash
# Create credentials for GitHub
GITHUB_TOKEN="your-github-token"

# Add repository to Argo CD
argocd repo add https://github.com/YuvrajSharma7/spring-boot-kubernetes.git \
  --username YuvrajSharma7 \
  --password $GITHUB_TOKEN
```

**Diagram: Argo CD Architecture**

```
GitHub Repository
│
├─ main branch
│  └─ k8s/
│     ├─ deployment.yaml
│     ├─ service.yaml
│     └─ ingress.yaml
│
└─ Argo CD Agent (in cluster)
   ├─ Polls Git every 3 minutes
   ├─ Compares desired (Git) vs actual (cluster)
   ├─ Auto-syncs if different
   └─ Updates Kubernetes resources
```

---

## **PHASE 4: CREATE KUBERNETES MANIFESTS** (30-45 mins)

### Step 6: Create Deployment Manifest

```bash
mkdir -p k8s

cat > k8s/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-boot-kubernetes
  labels:
    app: spring-boot-kubernetes
    version: v1.0.0
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  
  selector:
    matchLabels:
      app: spring-boot-kubernetes
  
  template:
    metadata:
      labels:
        app: spring-boot-kubernetes
        version: v1.0.0
    
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - spring-boot-kubernetes
              topologyKey: kubernetes.io/hostname
      
      containers:
      - name: spring-boot-app
        image: 123456789012.dkr.ecr.ap-south-1.amazonaws.com/spring-boot-kubernetes:v1.0.0
        imagePullPolicy: IfNotPresent
        
        ports:
        - containerPort: 8080
          name: http
          protocol: TCP
        
        env:
        - name: DB_HOST
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: host
        - name: DB_PORT
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: port
        - name: DB_NAME
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: name
        - name: DB_USERNAME
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: username
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
        
        resources:
          requests:
            cpu: 250m
            memory: 512Mi
          limits:
            cpu: 500m
            memory: 1Gi
        
        livenessProbe:
          httpGet:
            path: /actuator/health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        
        readinessProbe:
          httpGet:
            path: /actuator/health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 2
        
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 1000
          capabilities:
            drop:
            - ALL
EOF

echo "✅ Deployment manifest created"
```

**Diagram: Pod Lifecycle**

```
Deployment
│
├─ Creates ReplicaSet
│  ├─ pod-abc123
│  │  ├─ Waiting (pulling image from ECR)
│  │  ├─ ContainerCreating
│  │  ├─ Running
│  │  │  ├─ Liveness check: /actuator/health
│  │  │  └─ Readiness check: /actuator/health
│  │  └─ Ready (traffic can be sent)
│  │
│  └─ pod-def456
│     └─ (Same lifecycle)
│
└─ Ensures 2 replicas running at all times
   (If pod crashes, new one spawned)
```

### Step 7: Create Service Manifest

```bash
cat > k8s/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: spring-boot-kubernetes-service
  labels:
    app: spring-boot-kubernetes
spec:
  type: ClusterIP
  selector:
    app: spring-boot-kubernetes
  
  ports:
  - port: 8080
    targetPort: 8080
    protocol: TCP
    name: http
  
  sessionAffinity: None
EOF

echo "✅ Service manifest created"
```

**Diagram: Service Routing**

```
External Request (via Ingress)
│
└─ Service: spring-boot-kubernetes-service:8080 (ClusterIP)
   │
   ├─ Pod 1 (192.168.1.10:8080)  ← forwards to
   │
   └─ Pod 2 (192.168.1.11:8080)  ← round-robin
```

### Step 8: Create Ingress Manifest

```bash
cat > k8s/ingress.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: spring-boot-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  ingressClassName: nginx
  
  tls:
  - hosts:
    - myapp.haryana.com
    secretName: myapp-tls-secret
  
  rules:
  - host: myapp.haryana.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: spring-boot-kubernetes-service
            port:
              number: 8080
EOF

echo "✅ Ingress manifest created"
```

**Diagram: Ingress Traffic Flow**

```
User Browser Request
│
└─ myapp.haryana.com:443
   │
   ├─ DNS resolves to NLB IP
   │
   └─ NLB (AWS Load Balancer)
      └─ Forwards to NGINX Controller Pod:443
         │
         └─ NGINX reads Ingress rules
            └─ Rule: hostname=myapp.haryana.com → service:8080
               │
               └─ Sends request to Service (spring-boot-kubernetes-service:8080)
                  │
                  ├─ Service selects pod: app=spring-boot-kubernetes
                  │
                  ├─ Pod 1 (192.168.1.10)
                  │
                  └─ Pod 2 (192.168.1.11)
```

### Step 9: Create Secrets for Database

```bash
# Get RDS endpoint
DB_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier spring-boot-db \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

# Create secret
kubectl create secret generic db-credentials \
  --from-literal=host=$DB_HOST \
  --from-literal=port=5432 \
  --from-literal=name=mydb \
  --from-literal=username=dbadmin \
  --from-literal=password='YourSecurePassword123!' \
  --dry-run=client \
  -o yaml > k8s/secret.yaml

# Apply secret
kubectl apply -f k8s/secret.yaml

# Verify
kubectl get secret db-credentials
```

---

## **PHASE 5: DEPLOY TO EKS** (10-15 mins)

### Step 10: Apply Kubernetes Manifests

#### 10.1 Create Namespace (Optional)

```bash
# Create dedicated namespace
kubectl create namespace production

# Set as default context
kubectl config set-context --current --namespace=production
```

#### 10.2 Apply Manifests in Order

```bash
# 1. Create secrets first (needed by deployment)
kubectl apply -f k8s/secret.yaml

# 2. Apply deployment
kubectl apply -f k8s/deployment.yaml

# 3. Apply service
kubectl apply -f k8s/service.yaml

# 4. Apply ingress
kubectl apply -f k8s/ingress.yaml

echo "✅ All manifests applied"
```

#### 10.3 Wait for Pods to be Ready

```bash
# Watch pod status
kubectl get pods -w

# Expected output (wait until all show Running):
# NAME                                  READY   STATUS    RESTARTS   AGE
# spring-boot-kubernetes-abc123         1/1     Running   0          30s
# spring-boot-kubernetes-def456         1/1     Running   0          30s

# Verify health checks passing
kubectl describe pod spring-boot-kubernetes-abc123
```

**Diagram: Pod Startup Sequence**

```
Time: 0s
├─ Pods scheduled to nodes
│
├─ 5s: Container image pulled from ECR
│
├─ 10s: Container starts
│
├─ 15s: Application booting (Spring context loading)
│      └─ Connecting to RDS database
│      └─ Running Flyway migrations
│      └─ Loading configuration
│
├─ 25s: Liveness probe starts
│      └─ GET /actuator/health → SUCCESS
│
├─ 30s: Readiness probe starts
│      └─ GET /actuator/health → SUCCESS
│
└─ 32s: Pod becomes READY (traffic can be sent)
```

#### 10.4 Verify Service Endpoints

```bash
# Check service endpoints (should show pod IPs)
kubectl get endpoints spring-boot-kubernetes-service

# Expected output:
# NAME                                  ENDPOINTS                     AGE
# spring-boot-kubernetes-service        192.168.1.10:8080,192.168.1.11:8080   45s
```

#### 10.5 Verify Ingress

```bash
# Check ingress status
kubectl get ingress

# Wait for ADDRESS to be populated (takes 1-2 minutes)
watch 'kubectl get ingress'

# Expected output:
# NAME                    CLASS    HOSTS                ADDRESS
# spring-boot-ingress    nginx    myapp.haryana.com    k8s-ingressn-7ddea...elb.amazonaws.com
```

---

## **PHASE 6: DNS & SSL CONFIGURATION** (15-30 mins)

### Step 11: Get Load Balancer Information

```bash
# Get the AWS Load Balancer DNS
LB_DNS=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Load Balancer DNS: $LB_DNS"
# Example: k8s-ingressn-7ddea123abc456.ap-south-1.elb.amazonaws.com

# Resolve IP address
LB_IP=$(nslookup $LB_DNS | grep "Address:" | tail -1 | awk '{print $2}')
echo "Load Balancer IP: $LB_IP"
```

### Step 12: Configure DNS (Create CNAME Record)

**In your DNS provider (Route53, GoDaddy, etc.):**

```
Record Type:  CNAME
Name:         myapp.haryana.com
Value:        k8s-ingressn-7ddea123abc456.ap-south-1.elb.amazonaws.com
TTL:          300 (5 minutes - shorter for testing)
```

**Diagram: DNS Resolution**

```
User's Browser
│
└─ Resolves: myapp.haryana.com
   │
   └─ DNS Query to Route53
      │
      └─ CNAME Record
         └─ myapp.haryana.com → k8s-ingressn-7ddea...elb.amazonaws.com
            │
            └─ Returns NLB IP address
               │
               └─ Browser connects to NLB
```

#### 12.1 Verify DNS Resolution

```bash
# Wait 5-10 minutes for DNS propagation
nslookup myapp.haryana.com

# Expected output:
# Name: myapp.haryana.com
# Address: 10.123.45.67
# (Or CNAME: k8s-ingressn-7ddea...elb.amazonaws.com)
```

### Step 13: Verify SSL Certificate

```bash
# Check certificate status
kubectl get certificate

# Expected output:
# NAME                     READY   SECRET              AGE
# myapp-tls-secret        True    myapp-tls-secret    2m

# If READY=False, wait a bit more
# Cert-Manager typically takes 2-5 minutes

# Verify certificate details
kubectl describe certificate myapp-tls-secret
```

**Diagram: Certificate Lifecycle**

```
Time: 0 minutes
├─ Ingress with cert annotation applied
│
├─ 1 min: Cert-Manager creates Certificate resource
│
├─ 1-2 min: ACME challenge initiated
│
├─ 2 min: NGINX serves HTTP challenge
│
├─ 2-3 min: Let's Encrypt validates
│
├─ 3-4 min: Certificate issued
│
├─ 4 min: Secret created with certificate
│
└─ 5 min: NGINX loads certificate for HTTPS ✅
```

---

## **PHASE 7: VERIFICATION & TESTING** (10-20 mins)

### Step 14: Test HTTP Connectivity

#### 14.1 Test via Load Balancer DNS

```bash
# HTTP request with Host header
curl -i -H "Host: myapp.haryana.com" \
  http://k8s-ingressn-7ddea...elb.amazonaws.com

# Expected output:
# HTTP/1.1 301 Moved Permanently
# Location: https://myapp.haryana.com/
# (Redirects to HTTPS)
```

#### 14.2 Test via Domain Name (after DNS propagates)

```bash
# Test HTTP
curl -i http://myapp.haryana.com

# Expected:
# HTTP/1.1 301 Moved Permanently
# Location: https://myapp.haryana.com/
```

### Step 15: Test HTTPS Connectivity

```bash
# Test HTTPS
curl -i https://myapp.haryana.com

# Expected output:
# HTTP/2 200 OK
# Date: Wed, 25 Mar 2025 10:30:00 GMT
# Content-Type: application/json
# ...
# {"status":"UP"}  (Spring Boot health endpoint)
```

**Diagram: Request Flow for HTTPS**

```
User: curl https://myapp.haryana.com

Step 1: DNS Resolution
└─ myapp.haryana.com → 10.123.45.67 (NLB IP)

Step 2: TCP Handshake
└─ Client ↔ NLB (port 443)

Step 3: TLS Handshake
├─ Client: "Hello, TLS version 1.3"
├─ NLB: "Here's my certificate"
│  └─ Signed by Let's Encrypt ✅
└─ Client: "Certificate valid, continue"

Step 4: HTTPS Request
└─ Client sends: GET / (encrypted)
└─ NLB decrypts

Step 5: Route to NGINX
└─ NLB → NGINX Controller Pod (port 8080)
└─ NGINX reads Ingress rules
└─ Host: myapp.haryana.com → service:8080

Step 6: Route to Service
└─ Service (ClusterIP 10.100.50.123) → Pod IP

Step 7: Request to Application
└─ Pod 1 or Pod 2
└─ Spring Boot processes request
└─ Returns JSON response

Step 8: Response Back
└─ Application → Service → NGINX → NLB → Client
└─ Encrypted with TLS
```

### Step 16: Test Application Functionality

```bash
# Test health endpoint
curl https://myapp.haryana.com/actuator/health

# Expected:
# {"status":"UP","components":{"db":{"status":"UP"}}}

# Test database connectivity
curl https://myapp.haryana.com/api/users

# Expected:
# [List of users from database]

# Test creating data
curl -X POST https://myapp.haryana.com/api/users \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","email":"test@example.com"}'

# Expected:
# {"id":1,"username":"testuser","email":"test@example.com",...}
```

### Step 17: Browser Testing

1. **Open browser and navigate to:**
   ```
   https://myapp.haryana.com
   ```

2. **Verify:**
   - ✅ Page loads without errors
   - ✅ Padlock icon appears (HTTPS secure)
   - ✅ Certificate is from Let's Encrypt
   - ✅ No certificate warnings

3. **Test application functionality:**
   - ✅ Login works
   - ✅ Data can be created
   - ✅ Data can be retrieved

---

## Verification at Each Step

### Complete Verification Checklist

```
STEP 1: Infrastructure Setup ✓
├─ [ ] VPC with public/private subnets
├─ [ ] RDS PostgreSQL running
├─ [ ] EKS cluster with 2+ nodes
└─ [ ] kubectl access working

STEP 2: Docker Image ✓
├─ [ ] Docker image built successfully
├─ [ ] Image pushed to ECR
├─ [ ] Image pulls without errors
└─ [ ] Image size reasonable (<500MB)

STEP 3: NGINX Controller ✓
├─ [ ] Pod running: kubectl get pods -n ingress-nginx
├─ [ ] Service has EXTERNAL-IP (AWS DNS name)
├─ [ ] No pending state
└─ [ ] Controller logs show no errors

STEP 4: Cert-Manager ✓
├─ [ ] Pods running: kubectl get pods -n cert-manager
├─ [ ] ClusterIssuer status healthy
└─ [ ] No ACME errors

STEP 5: Argo CD (Optional) ✓
├─ [ ] Server pod running
├─ [ ] Git repo connected
└─ [ ] Syncing enabled

STEP 6: Deployment ✓
├─ [ ] Pods running: kubectl get pods
├─ [ ] All pods READY 1/1
├─ [ ] Liveness probes passing
├─ [ ] Readiness probes passing
└─ [ ] No restarts

STEP 7: Service ✓
├─ [ ] Service created: kubectl get svc
├─ [ ] Endpoints showing pod IPs
└─ [ ] Service is ClusterIP (not LoadBalancer)

STEP 8: Ingress ✓
├─ [ ] Ingress created: kubectl get ingress
├─ [ ] ADDRESS shows NLB DNS
├─ [ ] Certificate READY=True
└─ [ ] TLS secret exists

STEP 9: DNS ✓
├─ [ ] CNAME record created
├─ [ ] DNS resolves: nslookup myapp.haryana.com
└─ [ ] TTL respected (verify with multiple nslookups)

STEP 10: HTTPS ✓
├─ [ ] curl https:// returns 200
├─ [ ] Certificate chain valid
├─ [ ] No SSL warnings
└─ [ ] Browser shows padlock

STEP 11: Application ✓
├─ [ ] /actuator/health returns UP
├─ [ ] Database connectivity works
├─ [ ] API endpoints responding
└─ [ ] No application errors in logs
```

---

## Troubleshooting

### Common Issues & Resolutions

#### Issue 1: Pod Stuck in Pending

```bash
# Diagnose
kubectl describe pod <pod-name>

# Look for:
# - Insufficient CPU/memory
# - Image pull errors
# - Node selector mismatch

# Resolution
kubectl logs <pod-name>
kubectl get nodes
kubectl top nodes
```

#### Issue 2: Ingress ADDRESS Empty

```bash
# Diagnose
kubectl get ingress
kubectl describe ingress spring-boot-ingress

# Wait for controller
watch 'kubectl get ingress'

# Check controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# Resolution
# Usually just needs 1-2 minutes
```

#### Issue 3: Certificate Not Ready

```bash
# Check status
kubectl describe certificate myapp-tls-secret

# Check Cert-Manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Common issues:
# - DNS not yet propagated
# - ACME challenge failed
# - Let's Encrypt rate limited
```

#### Issue 4: Connection Refused

```bash
# Test connectivity
curl -v http://LB_DNS

# Check security groups
aws ec2 describe-security-groups --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME"

# Check subnets are tagged
aws ec2 describe-subnets --query 'Subnets[*].[SubnetId,Tags]'
```

---

## **FINAL DEPLOYMENT DIAGRAM: Complete Flow**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          PRODUCTION ENVIRONMENT                              │
│                                                                               │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                        INTERNET / USERS                              │   │
│  └────────────────────────────┬─────────────────────────────────────────┘   │
│                               │                                              │
│                    HTTPS://myapp.haryana.com                               │
│                               │                                              │
│  ┌────────────────────────────▼─────────────────────────────────────────┐   │
│  │                       DNS (Route53)                                   │   │
│  │   myapp.haryana.com → CNAME → k8s-ingressn-7ddea...elb.amazonaws   │   │
│  └────────────────────────────┬─────────────────────────────────────────┘   │
│                               │                                              │
│  ┌────────────────────────────▼─────────────────────────────────────────┐   │
│  │              AWS Load Balancer (NLB) [EXTERNAL]                       │   │
│  │  • Public IP (accessible from internet)                              │   │
│  │  • Listener: 443 → NGINX Pod                                         │   │
│  │  • Health Check: /health                                             │   │
│  └────────────────────────────┬─────────────────────────────────────────┘   │
│                               │                                              │
│  ┌────────────────────────────▼─────────────────────────────────────────┐   │
│  │                    EKS CLUSTER (ap-south-1)                           │   │
│  │                                                                       │   │
│  │  ┌──────────────────────────────────────────────────────────────┐   │   │
│  │  │         NGINX Ingress Controller (Deployment)               │   │   │
│  │  │  • Reads Ingress rules                                       │   │   │
│  │  │  • Terminates SSL/TLS                                        │   │   │
│  │  │  • Routes to backend service                                │   │   │
│  │  │  Replicas: 2                                                │   │   │
│  │  │  ├─ Pod (replica 1, zone A)                                │   │   │
│  │  │  └─ Pod (replica 2, zone B)                                │   │   │
│  │  └────────────────┬───────────────────────────────────────────┘   │   │
│  │                  │                                                │   │
│  │      Routes based on Ingress rules                              │   │
│  │      (Host: myapp.haryana.com → Service:8080)                 │   │
│  │                  │                                                │   │
│  │  ┌──────────────▼───────────────────────────────────────────┐   │   │
│  │  │  Spring Boot Service (ClusterIP)                         │   │   │
│  │  │  • kubernetes:8080                                       │   │   │
│  │  │  • ClusterIP: 10.100.50.123                             │   │   │
│  │  │  • Selects pods: app=spring-boot-kubernetes             │   │   │
│  │  │  • Load balances traffic                                │   │   │
│  │  └────────────────┬────────────────────────────────────────┘   │   │
│  │                   │                                               │   │
│  │         Service routes to pods (round-robin)                    │   │
│  │                   │                                               │   │
│  │  ┌────────────────┼──────────────────────────────────────────┐  │   │
│  │  │                │                                          │  │   │
│  │  ▼                ▼                                          │  │   │
│  │  ┌──────────────────────┐              ┌──────────────────┐ │  │   │
│  │  │   Spring Boot Pod 1  │              │Spring Boot Pod 2 │ │  │   │
│  │  │ (Node A, zone A)     │              │(Node B, zone B)  │ │  │   │
│  │  │                      │              │                  │ │  │   │
│  │  │ • JDK 21             │              │ • JDK 21         │ │  │   │
│  │  │ • Application code   │              │ • Application    │ │  │   │
│  │  │ • Port: 8080         │              │ • Port: 8080     │ │  │   │
│  │  │ • Liveness probe: ✓  │              │ • Liveness: ✓    │ │  │   │
│  │  │ • Readiness probe: ✓ │              │ • Readiness: ✓   │ │  │   │
│  │  │ • Resources: 512Mi   │              │ • Resources: 512 │ │  │   │
│  │  └──────────┬───────────┘              └────────┬─────────┘ │  │   │
│  │             │                                  │             │  │   │
│  │             │ TCP connection (5432)           │             │  │   │
│  │             │ SELECT * FROM users;            │             │  │   │
│  │             │ INSERT INTO users VALUES (...);  │             │  │   │
│  │             │                                  │             │  │   │
│  │             └──────────────┬───────────────────┘             │  │   │
│  │                            │                                 │  │   │
│  └────────────────────────────┼─────────────────────────────────┘  │   │
│                               │                                     │   │
│  ┌────────────────────────────▼─────────────────────────────────┐  │   │
│  │              AWS RDS PostgreSQL (EXTERNAL)                   │  │   │
│  │  • Multi-AZ (ap-south-1a, ap-south-1b)                      │  │   │
│  │  • Automated backups (7 days retention)                      │  │   │
│  │  • Encryption at rest (KMS)                                 │  │   │
│  │  • Database: mydb                                           │  │   │
│  │  • Tables: users, posts, audit_logs, etc.                  │  │   │
│  │  • Flyway migrations applied on startup                     │  │   │
│  └──────────────────────────────────────────────────────────────┘  │   │
│                                                                     │   │
│  ┌──────────────────────────────────────────────────────────────┐  │   │
│  │         Other K8s Components Running                         │  │   │
│  │  • Cert-Manager (manages SSL certificates)                 │  │   │
│  │  • CoreDNS (service discovery)                             │  │   │
│  │  • Metrics-Server (CPU/memory monitoring)                  │  │   │
│  │  • AWS Load Balancer Controller (manages NLB)              │  │   │
│  │  • Cluster Autoscaler (scales nodes)                       │  │   │
│  │  • HPA (scales pods based on CPU)                          │  │   │
│  └──────────────────────────────────────────────────────────────┘  │   │
│                                                                     │   │
└─────────────────────────────────────────────────────────────────────┘   │
```

---

## **COMPLETE DEPLOYMENT FLOW SUMMARY**

```
PHASE 1: INFRASTRUCTURE (AWS Setup)
├─ Create VPC with public/private subnets
├─ Create RDS PostgreSQL instance
├─ Create EKS cluster
├─ Create node groups (multi-AZ)
└─ Configure security groups and IAM roles

                            ↓

PHASE 2: BUILD & PUSH
├─ Maven build Spring Boot app
├─ Create Docker image
├─ Push to AWS ECR
└─ Tag with version (v1.0.0)

                            ↓

PHASE 3: INSTALL CONTROLLERS
├─ Install NGINX Ingress Controller (Helm)
├─ Install Cert-Manager (Helm)
├─ Install Argo CD (kubectl apply)
└─ Install monitoring (Prometheus/Grafana - optional)

                            ↓

PHASE 4: CREATE MANIFESTS
├─ deployment.yaml (Spring Boot pod definition)
├─ service.yaml (ClusterIP service)
├─ ingress.yaml (HTTPS routing)
├─ secret.yaml (database credentials)
└─ clusterissuer.yaml (Let's Encrypt)

                            ↓

PHASE 5: DEPLOY
├─ kubectl apply -f k8s/
├─ Wait for pods to be ready
└─ Verify health checks

                            ↓

PHASE 6: CONFIGURE DNS & SSL
├─ Get load balancer DNS from kubectl
├─ Create CNAME record in DNS provider
├─ Wait for DNS propagation (5-10 mins)
├─ Cert-Manager automatically issues certificate
└─ Certificate stored in K8s Secret

                            ↓

PHASE 7: VERIFY & TEST
├─ curl HTTP → 301 redirect
├─ curl HTTPS → 200 OK
├─ Browser → padlock icon
├─ Test application endpoints
└─ Verify database connectivity

                            ↓

PHASE 8: SETUP GITOPS (OPTIONAL)
├─ Push k8s/ manifests to Git
├─ Connect Argo CD to Git repo
├─ Enable auto-sync
└─ Future deployments: git push → Argo CD syncs

                            ↓

LIVE IN PRODUCTION! 🚀
```

---

## Time & Resource Estimates

| Phase | Duration | Resources |
|-------|----------|-----------|
| **Infrastructure Setup** | 1-2 hours | AWS account, permissions |
| **Docker Build & Push** | 10-15 min | Local machine, ECR |
| **Install Controllers** | 20-30 min | kubectl, Helm |
| **Create Manifests** | 15-20 min | YAML files, Git |
| **Deploy to EKS** | 5-10 min | kubectl |
| **DNS & SSL** | 15-20 min | DNS provider, wait time |
| **Verification & Testing** | 10-15 min | curl, browser |
| **Setup Argo CD** | 10-15 min | kubectl, GitHub token |
| **TOTAL** | **2-3.5 hours** | - |

---

## Post-Deployment Checklist

After going live:

```
✅ Immediate (First 5 minutes)
├─ Monitor error rate (should be 0%)
├─ Check response times (should be <1s)
├─ Monitor CPU/memory (should be <50%)
└─ Team confirms app accessible

✅ First 30 minutes
├─ Monitor for any pod crashes
├─ Check database connectivity
├─ Review application logs
└─ Verify all alerts are firing

✅ First 24 hours
├─ Monitor stability
├─ Check for any anomalies
├─ Document any issues
└─ Verify backup/restore works

✅ First 7 days
├─ Review performance metrics
├─ Adjust scaling parameters if needed
├─ Document lessons learned
└─ Plan any improvements
```

---

## **Success Confirmation**

When you see this, you've successfully deployed! 🎉

```
$ curl https://myapp.haryana.com/actuator/health

HTTP/2 200
Date: Wed, 25 Mar 2025 10:30:00 GMT
Content-Type: application/json

{"status":"UP","components":{"db":{"status":"UP"}}}

$ kubectl get all

NAME                                          READY   STATUS    RESTARTS
pod/spring-boot-kubernetes-abc123             1/1     Running   0
pod/spring-boot-kubernetes-def456             1/1     Running   0
pod/ingress-nginx-controller-xyz789          1/1     Running   0

SERVICE NAME                              TYPE           CLUSTER-IP
service/spring-boot-kubernetes-service   ClusterIP      10.100.50.123
service/ingress-nginx-controller         LoadBalancer   10.100.50.124

INGRESS NAME                    CLASS    HOSTS                   ADDRESS
ingress/spring-boot-ingress    nginx    myapp.haryana.com    k8s-ingressn-7ddea...

DEPLOYMENT NAME                     READY   UP-TO-DATE   AVAILABLE
deployment/spring-boot-kubernetes  2/2     2            2

$
```

**Your Spring Boot application is now running in production on EKS!** 🚀
