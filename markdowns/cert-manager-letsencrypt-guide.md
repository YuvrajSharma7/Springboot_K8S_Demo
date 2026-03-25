# 🔒 Production SSL/TLS with Cert-Manager & Let's Encrypt

## Overview

To set up Cert-Manager with Let's Encrypt, you are essentially adding an automated "Certificate Authority" inside your EKS cluster. This agent will talk to Let's Encrypt, prove you own the domain, and automatically rotate your SSL certificates every 90 days.

---

## 📋 Prerequisites

Before starting, ensure you have:

- An EKS cluster with NGINX Ingress Controller installed
- A custom domain (e.g., `myapp.haryana.com`)
- Access to your domain's DNS settings

---

## Step 1: Install Cert-Manager

First, install the Cert-Manager controllers using the official Jetstack manifests:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
```

Verify the installation by checking that the pods are in a Running state:

```bash
kubectl get pods -n cert-manager
```

You should see three pods running:
- `cert-manager-*`
- `cert-manager-webhook-*`
- `cert-manager-cainjector-*`

---

## Step 2: Create a ClusterIssuer

A **ClusterIssuer** tells Cert-Manager how to get certificates. We will use the ACME protocol with Let's Encrypt.

Save this as `k8s/issuer.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    # Use your actual email for expiry notifications
    email: your-email@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
    - http01:
        ingress:
          class: nginx
```

**Key Points:**

- `email`: Replace with your actual email address. Let's Encrypt will send expiry notifications here.
- `server`: Points to Let's Encrypt's production ACME server (use this for real certificates).
- `solvers`: Uses HTTP-01 validation via the NGINX Ingress Controller.

---

## Step 3: Update Your Ingress for HTTPS

Now, you tell your Ingress to use that Issuer and store the certificate in a Kubernetes Secret.

Update your `k8s/ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: spring-boot-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: "letsencrypt-prod"  # Must match metadata.name above
spec:
  tls:
  - hosts:
    - myapp.haryana.com  # Your actual domain
    secretName: myapp-tls-secret  # Cert-Manager will create this secret
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
```

**Key Changes:**

- Added `cert-manager.io/cluster-issuer` annotation pointing to your ClusterIssuer
- Added `tls` block with your domain and a secret name
- Cert-Manager will automatically create and manage the `myapp-tls-secret`

---

## Step 4: DNS Configuration

For Let's Encrypt to validate that you own the domain, your DNS records must point to your Ingress Controller's address.

```bash
# Get your Ingress Controller's external DNS name
kubectl get ingress spring-boot-ingress
```

Example output:
```
NAME                  CLASS    HOSTS              ADDRESS                                   PORTS
spring-boot-ingress   nginx    myapp.haryana.com  aaaa1111-222222.us-east-1.elb.amazonaws   80, 443
```

In your domain registrar (e.g., GoDaddy, AWS Route 53), add a **CNAME record**:

| Type  | Name                 | Value                                      |
|-------|----------------------|--------------------------------------------|
| CNAME | myapp.haryana.com    | `aaaa1111-222222.us-east-1.elb.amazonaws` |

Wait 5-10 minutes for DNS propagation.

---

## 🛡️ Production Verification

Once you push these manifests to GitHub and Argo CD syncs them, verify everything is working:

### 1. Check Certificate Status

```bash
kubectl get certificate
```

Expected output:
```
NAME                READY   SECRET            AGE
myapp-tls-secret    True    myapp-tls-secret  2m
```

The `READY` column should eventually say `True`. This can take 1-5 minutes.

### 2. Check the Challenge Status

If the certificate is stuck (not becoming READY), check the ACME challenge:

```bash
kubectl describe challenge
```

Common issues:
- **Domain not resolving**: Ensure DNS CNAME is correctly configured
- **Ingress not accessible**: Verify your NGINX Ingress Controller is running
- **Certificate issuer unreachable**: Check firewall/security group rules

### 3. Verify the Secret Was Created

```bash
kubectl get secret myapp-tls-secret
```

Cert-Manager should have created this secret automatically with your SSL certificate.

### 4. Test HTTPS Access

Visit your domain in a browser:

```
https://myapp.haryana.com
```

You should see:
- ✅ A padlock icon in the address bar
- ✅ "Secure" status (no warnings)
- ✅ Certificate issued by "Let's Encrypt"

You can also check certificate details:

```bash
curl -vI https://myapp.haryana.com
```

---

## 📚 File Structure

After setup, your Kubernetes manifests directory should look like:

```
k8s/
├── deployment.yaml      # Spring Boot deployment
├── service.yaml         # Service (NodePort/ClusterIP)
├── ingress.yaml         # Ingress with HTTPS
└── issuer.yaml          # ClusterIssuer for Let's Encrypt
```

Commit all files to Git and let Argo CD handle the deployment:

```bash
git add k8s/
git commit -m "Add Cert-Manager and HTTPS support"
git push origin main
```

---

## 🔄 Automatic Certificate Renewal

Cert-Manager automatically handles certificate renewal **before expiration**. You don't need to do anything! Let's Encrypt certificates are valid for 90 days, and Cert-Manager will:

1. ✅ Renew 30 days before expiration
2. ✅ Validate ownership again automatically
3. ✅ Update the secret with the new certificate
4. ✅ Your app continues serving HTTPS without downtime

---

## 🚨 Troubleshooting Common Issues

### Issue: Certificate Status Stuck on `False`

**Solution:**
```bash
# Check logs from Cert-Manager
kubectl logs -n cert-manager deploy/cert-manager

# Check the Certificate object for events
kubectl describe certificate myapp-tls-secret
```

### Issue: "Connection Not Secure" Warning

**Possible Causes:**
- DNS CNAME not propagated (wait 5-10 minutes)
- Ingress Controller not running properly
- Wrong domain name in certificate

**Solution:**
```bash
# Verify DNS resolution
nslookup myapp.haryana.com

# Check Ingress status
kubectl describe ingress spring-boot-ingress
```

### Issue: "404 Not Found" on HTTPS

**Solution:**
Verify your backend service is running:
```bash
kubectl get svc spring-boot-kubernetes-service
kubectl get pods -l app=spring-boot-kubernetes
```

---

## 📝 Summary: Complete Production Setup

Your production-ready infrastructure now includes:

1. ✅ **EKS Cluster** - Managed Kubernetes on AWS
2. ✅ **GitOps with Argo CD** - Continuous deployment from Git
3. ✅ **NGINX Ingress Controller** - Single entry point for external traffic
4. ✅ **Cert-Manager + Let's Encrypt** - Automated HTTPS/SSL certificates
5. ✅ **Automated Certificate Renewal** - 90-day certificate lifecycle handled automatically

**Your app is now secure, scalable, and production-ready!** 🎉

---

## 🔗 Useful Resources

- [Cert-Manager Documentation](https://cert-manager.io/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Kubernetes Ingress Documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)