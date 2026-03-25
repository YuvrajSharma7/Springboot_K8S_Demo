# 🚀 Kubernetes Ingress: Production-Ready External Access Guide

## Why Ingress is Production Ready

An **Ingress** is the standard "Production Ready" way to manage external access for several professional reasons:

### Cost Efficiency
One Load Balancer can route traffic to 50 different microservices based on the URL path (e.g., `/api` vs `/auth`), saving you from paying for 50 separate AWS ELBs.

### SSL/TLS Termination
You can manage your HTTPS certificates in one place (the Ingress) rather than inside every Spring Boot app.

### Domain Routing
It allows you to use actual hostnames like `api.yourdomain.com`.

---

## 🛠️ The 3-Step Ingress Setup

To move from a LoadBalancer service to an Ingress, you need to change your architecture slightly.

### Step 1: Change Service to NodePort or ClusterIP

Since the Ingress will now sit in front of your service, the service no longer needs to be a LoadBalancer. Update your `k8s/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: spring-boot-kubernetes-service
spec:
  type: NodePort  # Or ClusterIP if the Ingress is inside the cluster
  selector:
    app: spring-boot-kubernetes
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080
```

### Step 2: Install an Ingress Controller

Think of the **Ingress Resource** (the YAML) as a "Rulebook" and the **Ingress Controller** as the "Security Guard" who reads those rules.

On EKS, the most common choices are:

- **NGINX Ingress Controller**: Very popular and flexible
- **AWS Load Balancer Controller**: Creates an AWS Application Load Balancer (ALB) automatically

**Installing NGINX Ingress Controller:**

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/aws/deploy.yaml
```

### Step 3: Create the Ingress Resource

Create a new file named `k8s/ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: spring-boot-ingress
  annotations:
    # If using NGINX:
    kubernetes.io/ingress.class: nginx
    # If using AWS ALB:
    # alb.ingress.kubernetes.io/scheme: internet-facing
spec:
  rules:
  - host: myapp.haryana.com  # Your custom domain
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: spring-boot-kubernetes-service
            port:
              number: 8080
```

---

## 🏗️ Production Comparison: Service vs Ingress

| Feature | Service (LoadBalancer) | Ingress |
|---------|------------------------|---------|
| **AWS Resource** | Creates 1 Classic/Network LB per Service | Creates 1 ALB for many Services |
| **Cost** | High (expensive per app) | Lower (shared resource) |
| **SSL/TLS** | Difficult to manage at scale | Easy (Cert-Manager integration) |
| **Path Routing** | Not supported | Supported (e.g., `/app1`, `/app2`) |

---

## ✅ Verification

After deploying your Ingress, verify it's working:

```bash
# Check the Ingress status
kubectl get ingress

# Find the external address (LoadBalancer DNS)
kubectl describe ingress spring-boot-ingress

# Access your app using the Ingress address
curl http://<ingress-address>/
```

---

## 📋 Integration with Argo CD

Add the `k8s/ingress.yaml` file to your Git repository alongside your other Kubernetes manifests. Argo CD will automatically sync and deploy it:

```
k8s/
├── deployment.yaml
├── service.yaml
└── ingress.yaml  # Add this file
```

Once committed and pushed, Argo CD will apply the Ingress resource to your EKS cluster automatically.

---

## 🎯 Next Steps

1. ✅ Update your Service to `NodePort` or `ClusterIP`
2. ✅ Install your chosen Ingress Controller (NGINX or AWS ALB)
3. ✅ Create and deploy the Ingress manifest
4. ✅ Update your DNS records to point to the Ingress address
5. ✅ Set up SSL/TLS certificates (optional but recommended for production)