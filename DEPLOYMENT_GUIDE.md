# GitOps Deployment Guide: Spring Boot App on AWS EKS with Argo CD

---

## Step 1: Infrastructure Preparation (AWS)

### 1.1 Create Amazon ECR Repository
- Navigate to the **AWS ECR Console**.
- Create a **private repository** named `gitops-k8s-repo` in region `ap-south-1`.

### 1.2 Create Amazon EKS Cluster
- Provision an EKS cluster with **managed node groups**.

### 1.3 Configure kubectl Access
After the cluster is created, configure your local `kubeconfig` to connect to it:

```bash
aws eks update-kubeconfig --region ap-south-1 --name <your-cluster-name>

# Verify
kubectl get nodes
```

### 1.4 Create IAM Credentials

#### CI User (for GitHub Actions — Push to ECR)
- Create a **non-root IAM user**.
- Assign the `AmazonEC2ContainerRegistryPowerUser` policy.
- Generate an **Access Key ID** and **Secret Access Key**.
- Ensure there are no trailing spaces or newlines when copying these keys.

#### EKS Node Group Role (for Pulling Images from ECR)
- Attach the `AmazonEC2ContainerRegistryReadOnly` policy to your **EKS node group IAM role**:

```bash
aws iam attach-role-policy \
  --role-name <your-eks-node-role-name> \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

> **Why?** Your CI user has push access, but EKS worker nodes need **pull** access to download images from ECR. Without this, pods will fail with `ImagePullBackOff`.

### 1.5 (Recommended) Set Up OIDC for GitHub Actions
Instead of storing long-lived AWS keys, use **OIDC federation** for a more secure setup. See [Step 3 — Security Note](#security-note-use-oidc-instead-of-static-keys) for details.

---

## Step 2: Application & Kubernetes Manifests

### 2.1 Create the Application
- Generate a **Spring Boot application** (Java 21, Maven) with the `spring-boot-starter-actuator` dependency for health checks.

### 2.2 Create the Dockerfile
- Add a standard Dockerfile to the project root to package the generated `.jar`.

### 2.3 Create a Kubernetes Namespace
Create a dedicated namespace for your application:

```bash
kubectl create namespace spring-boot-app
```

### 2.4 Create Kubernetes Manifests
Create a `k8s/` directory at the root of your project.

#### `k8s/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-boot-kubernetes
  namespace: spring-boot-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: spring-boot-kubernetes
  template:
    metadata:
      labels:
        app: spring-boot-kubernetes
    spec:
      containers:
        - name: spring-boot-app
          # The image tag below will be dynamically replaced by GitHub Actions
          image: 123456789012.dkr.ecr.ap-south-1.amazonaws.com/gitops-k8s-repo:latest
          ports:
            - containerPort: 8080
          resources:
            requests:
              memory: "256Mi"
              cpu: "250m"
            limits:
              memory: "512Mi"
              cpu: "500m"
          readinessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
```

#### `k8s/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: spring-boot-kubernetes-service
  namespace: spring-boot-app
spec:
  type: LoadBalancer
  selector:
    app: spring-boot-kubernetes
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080
```

---

## Step 3: CI Pipeline (GitHub Actions)

### 3.1 Configure Repository Secrets
Navigate to **Settings > Secrets and variables > Actions > Repository secrets** and add:
- `ACCESS_KEY`: Your AWS Access Key ID.
- `SECRET_ACCESS_KEY`: Your AWS Secret Access Key.

### 3.2 Grant GitHub Actions Write Permissions (Crucial Step)
By default, GitHub Actions cannot push commits back to your repository. To allow the GitOps hand-off:
1. Go to your repository **Settings**.
2. Navigate to **Actions > General**.
3. Scroll down to **Workflow permissions**.
4. Select **Read and write permissions**.
5. Click **Save**.

### 3.3 Create the `ci.yml` Workflow
Create `.github/workflows/ci.yml`.

> **Troubleshooting Note (ECR Login Hash Error):** During setup, the standard `aws-actions/configure-aws-credentials` action failed with a Signature Version 4 hash error (`Invalid key=value pair (missing equal-sign)`). This is often caused by invisible characters or action-specific masking bugs. To resolve this, we bypassed the action and used a **Direct Login Method** by injecting the environment variables directly into the shell.

```yaml
name: Build and Push to ECR

on:
  push:
    branches: [ "main" ]
    paths-ignore:
      - 'k8s/**'    # Prevent infinite CI loop when manifests are updated

permissions:
  contents: write

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Set up JDK 21
        uses: actions/setup-java@v4
        with:
          java-version: '21'
          distribution: 'temurin'
          cache: maven

      - name: Build with Maven
        run: mvn clean package -DskipTests

      - name: Login to Amazon ECR (Direct Method)
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.ACCESS_KEY }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.SECRET_ACCESS_KEY }}
          ECR_REGISTRY: 123456789012.dkr.ecr.ap-south-1.amazonaws.com
        run: |
          aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin $ECR_REGISTRY

      - name: Build, tag, and push image to Amazon ECR
        env:
          ECR_REGISTRY: 123456789012.dkr.ecr.ap-south-1.amazonaws.com
          ECR_REPOSITORY: gitops-k8s-repo
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG

      - name: Update Deployment Manifest
        env:
          ECR_REGISTRY: 123456789012.dkr.ecr.ap-south-1.amazonaws.com
        run: |
          git config --global user.name "github-actions"
          git config --global user.email "github-actions@github.com"
          sed -i "s|image:.*|image: $ECR_REGISTRY/gitops-k8s-repo:${{ github.sha }}|g" k8s/deployment.yaml
          git add k8s/
          git commit -m "Update image tag to ${{ github.sha }} [skip ci]"
          git push
```

### Security Note: Use OIDC Instead of Static Keys

For production, replace static AWS keys with **OIDC federation**:

```yaml
permissions:
  id-token: write   # Required for OIDC
  contents: write

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Configure AWS Credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/GitHubActionsRole
          aws-region: ap-south-1
```

This eliminates the need for `ACCESS_KEY` and `SECRET_ACCESS_KEY` secrets entirely.

---

## Step 4: Continuous Delivery (Argo CD Setup)

### 4.1 Install Argo CD on EKS

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
# If above command fails in cloud shell specifically then use below command
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 4.2 Access the Argo CD UI

#### Recommended: Port Forwarding (Secure)

```bash
# Configure AWS CLI with your credentials in local terminal (not cloud shell) then execute below commands
export AWS_ACCESS_KEY_ID="aws access key"
export AWS_SECRET_ACCESS_KEY="aws secret key"
export AWS_DEFAULT_REGION="ap-south-1"
aws eks update-kubeconfig --region ap-south-1 --name gitops-k8s-aks-cluster
# Verify kubectl access
kubectl get nodes
# Port forward Argo CD server to localhost, create a secure tunnel to the cluster
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Access at: https://localhost:8080
```

#### Alternative: Expose as LoadBalancer (Less Secure)

```bash
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```

> ⚠️ **Security Warning:** Exposing Argo CD directly to the internet is a security risk. If you must do this, place it behind an **Ingress with TLS and authentication**.

### 4.3 Retrieve the Login Credentials

```bash
# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

- **Username:** `admin`
- **Password:** output of the command above.

If using LoadBalancer, get the URL:

```bash
kubectl get svc argocd-server -n argocd
# Copy the EXTERNAL-IP. Wait 2-3 minutes for DNS to propagate.
```

### 4.4 Change the Default Admin Password

```bash
# Install Argo CD CLI on your local machine (not cloud shell)
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/

# Login and change password
argocd login localhost:8080
argocd account update-password
```

### 4.5 Connect the GitHub Repository (Required for Private Repos)

If your repository is **private**, Argo CD needs credentials to clone it:

1. In the Argo CD UI: **Settings → Repositories → Connect Repo**
2. Choose **HTTPS** method.
3. Provide:
    - **Repository URL:** `https://github.com/<owner>/<repo>.git`
    - **Username:** your GitHub username
    - **Password:** a GitHub **Personal Access Token** (with `repo` scope)

### 4.6 Create the Argo CD Application

In the Argo CD UI:
1. Click **New App**.
2. Set **Application Name:** `spring-boot-kubernetes`
3. Set **Project:** `default`
4. Set **Sync Policy:** `Automatic`
    - ✅ Enable **Prune Resources** — deletes resources removed from Git.
    - ✅ Enable **Self Heal** — reverts manual cluster changes to match Git.
5. Set **Repository URL:** your GitHub repo URL.
6. Set **Path:** `k8s/`
7. Set **Cluster URL:** `https://kubernetes.default.svc` (in-cluster)
8. Set **Namespace:** `spring-boot-app`
9. Click **Create**.

---

## Step 5: EKS CLI Troubleshooting

### Issue 1: `dial tcp 127.0.0.1:8080: connect: connection refused`

**Cause:** The kubeconfig session expired.

**Fix:** Refresh it by pointing kubectl back to your cluster:

```bash
aws eks update-kubeconfig --region ap-south-1 --name <your-cluster-name>
```

### Issue 2: `the server has asked for the client to provide credentials`

**Cause:** EKS requires IAM authentication, but your shell session doesn't have your keys exported.

**Fix:**

```bash
export AWS_ACCESS_KEY_ID="your_access_key"
export AWS_SECRET_ACCESS_KEY="your_secret_key"
export AWS_DEFAULT_REGION="ap-south-1"
```

Verify with:

```bash
kubectl get nodes
```

---

## Step 6: Final Verification & Access

Once Argo CD syncs your application, it will create both the **Deployment** and the **Service** defined in the `k8s/` folder.

### Get the Application URL:

```bash
kubectl get svc spring-boot-kubernetes-service -n spring-boot-app
```

### Access the App:

Copy the `EXTERNAL-IP` from the command output. Open your browser and navigate to:

```
http://<EXTERNAL-IP>:8080
```

---

## Appendix: Summary of All Changes

| # | Item | Category |
|---|---|---|
| 1 | ECR pull permissions on EKS node IAM role | 🔴 Critical |
| 2 | `aws eks update-kubeconfig` after cluster creation | 🔴 Critical |
| 3 | Argo CD repo authentication (for private repos) | 🔴 Critical |
| 4 | Dedicated Kubernetes namespace | 🟡 Best Practice |
| 5 | Resource requests/limits on pods | 🟡 Best Practice |
| 6 | Readiness/Liveness probes using Actuator | 🟡 Best Practice |
| 7 | Argo CD access via port-forward (not public LB) | 🟡 Security |
| 8 | Change Argo CD default admin password | 🟡 Security |
| 9 | Use OIDC instead of static AWS keys | 🟡 Security |
| 10 | `paths-ignore: k8s/**` to prevent CI loops | 🟢 Improvement |
| 11 | Argo CD prune + self-heal settings | 🟢 Improvement |