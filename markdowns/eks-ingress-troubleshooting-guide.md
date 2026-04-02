# 🛠️ EKS Ingress Troubleshooting: The "Subnet Match" & Connectivity Guide

## Overview

Ingress setup is often where things mysteriously break. The `EXTERNAL-IP` stays `<pending>` forever, or the Ingress shows no `ADDRESS`, leaving you wondering: "Why can't I access my app?"

This guide walks through the **most common Ingress issues** and their solutions, specifically for **NGINX Ingress Controller on EKS**.

---

## The Problem: Ingress Stuck in "Pending" State

### What It Looks Like

```bash
$ kubectl get svc -n ingress-nginx

NAME                      TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)
ingress-nginx-controller  LoadBalancer   10.100.50.123   <pending>     80:30123/TCP,443:30456/TCP
```

The EXTERNAL-IP never gets assigned (stuck at `<pending>`).

You're waiting... waiting... waiting... ☕

Then you check the events:

```bash
$ kubectl describe svc ingress-nginx-controller -n ingress-nginx

...
Events:
  Type     Reason       Age     From     Message
  ----     ------       ----    ----     -------
  Warning  SyncLoadBalancer   5m    service-controller  Error syncing load balancer: failed to ensure load balancer...
  Error    CreateFailed       4m    aws-lb-controller   Unable to resolve at least one subnet. VPC 'vpc-xxx' and tags...
```

### The Root Cause

AWS Load Balancer Controller is searching for subnets with specific tags. By default, it looks for **internal subnets** with tag `kubernetes.io/role/internal-elb`.

If you don't have subnets tagged for internal load balancers, OR if you want a **public/internet-facing** load balancer, AWS can't find a matching subnet.

**Error Message:**
```
Failed build model due to unable to resolve at least one subnet 
(0 match VPC and tags: [kubernetes.io/role/internal-elb])
```

---

## 🔍 Diagnosis: Understanding the Issue

### 1.1 Check Your VPC Subnets

First, let's see what subnets you have and how they're tagged:

```bash
# Get your EKS cluster's VPC
CLUSTER_NAME="spring-boot-eks-cluster"
VPC_ID=$(aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --query 'cluster.resourcesVpcConfig.vpcId' \
  --output text)

echo "VPC ID: $VPC_ID"

# List all subnets in the VPC with their tags
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[*].[SubnetId,AvailabilityZone,Tags[?Key==`kubernetes.io/role/elb`].Value[0],Tags[?Key==`kubernetes.io/role/internal-elb`].Value[0]]' \
  --output table
```

**Expected Output:**
```
SubnetId           AZ              ELB Role      Internal-ELB Role
subnet-1a2b3c4d   ap-south-1a    shared         shared
subnet-5e6f7g8h   ap-south-1b                   shared
subnet-9i0j1k2l   ap-south-1c    shared
```

### 1.2 Understand Subnet Tagging

AWS Load Balancer Controller looks for these tags:

| Tag | Purpose | Subnet Type |
|-----|---------|-------------|
| `kubernetes.io/role/elb=shared` or `owned` | **Public/Internet-facing** load balancers | Public subnets (with route to IGW) |
| `kubernetes.io/role/internal-elb=shared` or `owned` | **Internal** load balancers | Private subnets (no route to internet) |

### 1.3 Check Your Service Annotations

```bash
# Check what annotations the NGINX controller service has
kubectl get svc ingress-nginx-controller -n ingress-nginx -o yaml | grep -A5 "annotations:"
```

**Expected if public:**
```yaml
annotations:
  service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
  service.beta.kubernetes.io/aws-load-balancer-type: nlb
```

**Expected if private:**
```yaml
annotations:
  service.beta.kubernetes.io/aws-load-balancer-scheme: internal
  service.beta.kubernetes.io/aws-load-balancer-type: nlb
```

### 1.4 The Missing Piece

If you don't have the right annotations, AWS doesn't know:
- Should this be public or private?
- Where should I place the load balancer?
- What subnets should I use?

**Solution: Add the right annotations!** ⬇️

---

## 🛠️ The Fix: Update Service Annotations

### Option A: Quick Fix (Command Line)

If you already have NGINX Ingress Controller installed but the service is pending:

```bash
# Make the load balancer internet-facing (public)
kubectl annotate service ingress-nginx-controller \
  -n ingress-nginx \
  --overwrite \
  service.beta.kubernetes.io/aws-load-balancer-scheme=internet-facing

# Set the load balancer type to NLB (Network Load Balancer)
kubectl annotate service ingress-nginx-controller \
  -n ingress-nginx \
  --overwrite \
  service.beta.kubernetes.io/aws-load-balancer-type=nlb
```

**Wait 2-3 minutes**, then check:

```bash
kubectl get svc -n ingress-nginx

# Expected output:
# NAME                      TYPE           CLUSTER-IP      EXTERNAL-IP
# ingress-nginx-controller  LoadBalancer   10.100.50.123   k8s-ingressn-7ddea...ap-south-1.elb.amazonaws.com
```

✅ **EXTERNAL-IP should now show an AWS DNS name!**

### Option B: Permanent Fix (YAML Manifest)

If installing NGINX Ingress Controller fresh, ensure the service has proper annotations.

**Example: values-nginx.yaml (for Helm)**

```yaml
# For Helm install, create values file
controller:
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
      service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
      service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "tcp"
```

**Install with Helm:**

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --values values-nginx.yaml
```

**Or, if using raw Kubernetes manifests:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
  labels:
    app.kubernetes.io/name: ingress-nginx
spec:
  type: LoadBalancer
  annotations:
    # ⬇️ Add these annotations
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "tcp"
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/instance: ingress-nginx
    app.kubernetes.io/component: controller
  ports:
  - port: 80
    protocol: TCP
    targetPort: http
    name: http
  - port: 443
    protocol: TCP
    targetPort: https
    name: https
```

### Option C: Public vs. Private Load Balancer Choice

**For public (internet-facing):**
```yaml
annotations:
  service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
```

**For private (internal only):**
```yaml
annotations:
  service.beta.kubernetes.io/aws-load-balancer-scheme: "internal"
```

---

## 🌐 Connectivity Verification: Making It Actually Work

Once your EXTERNAL-IP is assigned, you need to verify connectivity.

### Step 1: Get the Load Balancer DNS Name

```bash
# Get the EXTERNAL-IP (AWS DNS name)
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Example output:
# EXTERNAL-IP: k8s-ingressn-7ddea123abc456.ap-south-1.elb.amazonaws.com
```

Save this for the next steps.

### Step 2: Verify Ingress Has Received the Address

```bash
# Check if your Ingress rule has picked up the load balancer address
kubectl get ingress

# Expected output:
# NAME              CLASS   HOSTS              ADDRESS                                        PORTS
# spring-boot-ingress  nginx   myapp.haryana.com  k8s-ingressn-7ddea...ap-south-1.elb.amazonaws.com  80, 443
```

If `ADDRESS` is empty, wait 2-3 minutes more (ingress controller is propagating).

### Step 3: Test with curl (Host Header Spoofing)

Your domain `myapp.haryana.com` might not resolve to the load balancer yet (DNS not updated), so we use a Host header:

```bash
# Using the load balancer DNS, tell it we're requesting myapp.haryana.com
curl -i -H "Host: myapp.haryana.com" \
  http://k8s-ingressn-7ddea...ap-south-1.elb.amazonaws.com

# Expected output:
# HTTP/1.1 200 OK
# Content-Type: application/json
# ...
# [response from your app]
```

### Step 4: Verify HTTPS Works (After Certificate Is Ready)

```bash
# Test HTTPS (will show warning if cert not yet ready)
curl -i -H "Host: myapp.haryana.com" \
  https://k8s-ingressn-7ddea...ap-south-1.elb.amazonaws.com \
  --insecure

# After Cert-Manager provisions certificate (takes 2-5 min):
curl -i -H "Host: myapp.haryana.com" \
  https://k8s-ingressn-7ddea...ap-south-1.elb.amazonaws.com

# Expected:
# HTTP/2 200 OK
# [response without certificate warnings]
```

### Step 5: Point Your Domain DNS to Load Balancer

Now that everything works via the LB DNS, point your actual domain there.

**In your DNS provider (Route53, GoDaddy, Cloudflare, etc.):**

Create a CNAME record:

```
Name: myapp.haryana.com
Type: CNAME
Value: k8s-ingressn-7ddea...ap-south-1.elb.amazonaws.com
TTL: 300 (5 minutes, shorter while testing)
```

**Wait for DNS propagation (5-10 minutes):**

```bash
# Verify DNS resolves to the load balancer
nslookup myapp.haryana.com

# Expected output:
# Non-authoritative answer:
# Name: myapp.haryana.com
# Address: 10.123.45.67  (or CNAME to the LB DNS)
```

### Step 6: Test Full End-to-End Access

```bash
# HTTP (should redirect to HTTPS)
curl -I http://myapp.haryana.com

# Expected:
# HTTP/1.1 301 Moved Permanently
# Location: https://myapp.haryana.com

# HTTPS (after DNS propagates and certificate is ready)
curl -I https://myapp.haryana.com

# Expected:
# HTTP/2 200 OK
# (or 200 if HTTP/1.1)
```

**Or open in browser:**
```
https://myapp.haryana.com
```

You should see the padlock icon and your app! ✅

---

## 🚨 Common Issues & Solutions

### Issue 1: EXTERNAL-IP Still Pending After 10 Minutes

**Diagnosis:**

```bash
# Check service events
kubectl describe svc ingress-nginx-controller -n ingress-nginx

# Look for error message
# Common errors:
# - "unable to resolve at least one subnet"
# - "Subnet not found"
# - "No subnets found with tags"
```

**Solution:**

1. **Check subnets have proper tags:**
   ```bash
   aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
     --query 'Subnets[*].[SubnetId,Tags]' --output table
   ```

2. **If missing tags, add them:**
   ```bash
   # For public subnets (internet-facing LB)
   SUBNET_ID="subnet-1a2b3c4d"
   aws ec2 create-tags --resources $SUBNET_ID \
     --tags Key=kubernetes.io/role/elb,Value=shared
   
   # For private subnets (internal LB)
   aws ec2 create-tags --resources $SUBNET_ID \
     --tags Key=kubernetes.io/role/internal-elb,Value=shared
   ```

3. **Delete and recreate the service:**
   ```bash
   kubectl delete svc ingress-nginx-controller -n ingress-nginx
   kubectl apply -f ingress-nginx-service.yaml  # with correct annotations
   ```

4. **Wait 3-5 minutes** for AWS to provision the load balancer

### Issue 2: Ingress ADDRESS is Empty

**Diagnosis:**

```bash
kubectl get ingress
# ADDRESS column is empty
```

**Causes:**
- Ingress Controller not running
- Ingress class mismatch

**Solution:**

```bash
# 1. Check NGINX controller is running
kubectl get pods -n ingress-nginx
# Expected: ingress-nginx-controller pod in Running state

# 2. Check Ingress class name matches
kubectl get ingress -o yaml | grep -A2 "spec:"
# Expected: ingressClassName: nginx

# 3. Check Ingress Controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=20

# 4. Wait 2-3 minutes for controller to process
watch 'kubectl get ingress'

# 5. If still empty, restart the controller
kubectl rollout restart deployment/ingress-nginx-controller -n ingress-nginx
```

### Issue 3: Connection Refused / Timeout

**Diagnosis:**

```bash
curl -i -H "Host: myapp.haryana.com" http://k8s-ingressn-7ddea...elb.amazonaws.com
# curl: (7) Failed to connect to k8s-ingressn... port 80: Connection refused
```

**Causes:**
- Security group blocking traffic
- Application not running
- Service not routing to pods

**Solution:**

```bash
# 1. Check app is running
kubectl get pods -l app=spring-boot-kubernetes
# Expected: At least 1 pod in Running state

# 2. Check service has endpoints
kubectl get endpoints spring-boot-kubernetes-service
# Expected: Shows pod IPs under ENDPOINTS

# 3. Check security group rules
CLUSTER_NAME="spring-boot-eks-cluster"
SECURITY_GROUP_ID=$(aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --query 'cluster.resourcesVpcConfig.securityGroupIds[0]' \
  --output text)

aws ec2 describe-security-groups --group-ids $SECURITY_GROUP_ID \
  --query 'SecurityGroups[0].IpPermissions' --output table

# Expected: Allow ingress on port 80 and 443 from 0.0.0.0/0

# 4. Check ALB security group (separate from node SG)
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=*ingress*" \
  --query 'SecurityGroups[0].IpPermissions' --output table

# 5. If missing rules, add them
aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP_ID \
  --protocol tcp --port 80 --cidr 0.0.0.0/0
```

### Issue 4: 503 Service Unavailable

**Diagnosis:**

```bash
curl -i -H "Host: myapp.haryana.com" http://k8s-ingressn-7ddea...elb.amazonaws.com
# HTTP/1.1 503 Service Unavailable
```

**Causes:**
- Application not healthy (failed readiness probe)
- No endpoints available
- App crashed

**Solution:**

```bash
# 1. Check pod health
kubectl get pods -l app=spring-boot-kubernetes
# Expected: STATUS = Running, READY = 1/1

# 2. Check readiness probe
kubectl describe pod <pod-name> | grep -A5 "Readiness"
# Expected: Probes are passing

# 3. Check app logs
kubectl logs -l app=spring-boot-kubernetes --tail=50
# Look for errors preventing startup

# 4. Check service endpoints
kubectl get endpoints spring-boot-kubernetes-service
# Expected: Shows pod IP addresses

# 5. Restart pod if needed
kubectl delete pod -l app=spring-boot-kubernetes
# Kubernetes will respawn via deployment
```

### Issue 5: Certificate Not Trusted (HTTPS)

**Diagnosis:**

```bash
curl https://myapp.haryana.com
# curl: (60) SSL certificate problem: self signed certificate
```

**Causes:**
- Cert-Manager hasn't issued certificate yet
- Certificate validation failed

**Solution:**

```bash
# 1. Check certificate status
kubectl get certificate myapp-tls-secret
# Expected: READY=True

# 2. If READY=False, check why
kubectl describe certificate myapp-tls-secret
# Look under "Status" section for error messages

# 3. Check certificate was created
kubectl get secret myapp-tls-secret
# Expected: Secret exists

# 4. View certificate details
kubectl get secret myapp-tls-secret -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout | grep -A2 "Validity"

# 5. If certificate is self-signed, wait for Cert-Manager
# Cert-Manager typically takes 2-5 minutes
watch 'kubectl get certificate myapp-tls-secret'

# 6. Check Cert-Manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=20
```

---

## 📋 Verification Checklist

### Complete Ingress Setup Verification

```
Item                              Command                                      Success Criteria
─────────────────────────────────────────────────────────────────────────────────────────────
1. NGINX Controller Pod           kubectl get pods -n ingress-nginx             1/1 Running
2. Service EXTERNAL-IP            kubectl get svc -n ingress-nginx              AWS DNS name (not <pending>)
3. Service Annotations            kubectl get svc -n ingress-nginx -o yaml      Has aws-load-balancer-scheme
4. Ingress Resource Created        kubectl get ingress                           At least one ingress present
5. Ingress Class Correct           kubectl get ingress -o yaml                   ingressClassName: nginx
6. Ingress ADDRESS Populated       kubectl get ingress                           ADDRESS shows LB DNS
7. App Pods Running                kubectl get pods -l app=spring-boot...       At least 1/1 Running
8. Service Endpoints               kubectl get endpoints spring-boot...         Shows pod IPs
9. curl via LB DNS                 curl -H "Host: myapp..." http://LB-DNS       200 OK response
10. DNS Resolution                 nslookup myapp.haryana.com                   Resolves to LB IP/DNS
11. HTTPS Works                    curl https://myapp.haryana.com               200 OK (after cert ready)
12. Certificate Valid              curl https://myapp.haryana.com               No SSL warnings
13. HTTP → HTTPS Redirect          curl http://myapp.haryana.com                301 redirect to HTTPS
14. App Accessible                 Browser: https://myapp.haryana.com           Page loads with padlock ✅
```

---

## 🔧 Complete Troubleshooting Workflow

Use this when everything is broken:

```bash
#!/bin/bash
# Complete Ingress Troubleshooting Script

echo "=== Step 1: NGINX Controller Status ==="
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
echo ""

echo "=== Step 2: Service Annotations ==="
kubectl get svc ingress-nginx-controller -n ingress-nginx -o json | jq '.metadata.annotations'
echo ""

echo "=== Step 3: Ingress Status ==="
kubectl get ingress
kubectl describe ingress spring-boot-ingress
echo ""

echo "=== Step 4: App Status ==="
kubectl get pods -l app=spring-boot-kubernetes
kubectl get svc spring-boot-kubernetes-service
kubectl get endpoints spring-boot-kubernetes-service
echo ""

echo "=== Step 5: Certificate Status ==="
kubectl get certificate
kubectl describe certificate myapp-tls-secret
echo ""

echo "=== Step 6: Controller Logs (last 20 lines) ==="
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=20
echo ""

echo "=== Step 7: Try Connectivity ==="
LB_DNS=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Load Balancer DNS: $LB_DNS"
echo "Testing connectivity..."
curl -i -H "Host: myapp.haryana.com" http://$LB_DNS 2>&1 | head -20
```

Run this and review output to identify the issue.

---

## 📊 Summary Table for Master Documentation

```
Resource              Status Check                          Success Criteria
──────────────────────────────────────────────────────────────────────────────────
Controller Pod        kubectl get pods -n ingress-nginx     1/1 Running
Controller Service    kubectl get svc -n ingress-nginx      EXTERNAL-IP is AWS DNS
Service Annotations   kubectl get svc -o yaml               Has internet-facing scheme
Ingress Rule          kubectl get ingress                   ADDRESS is populated
Ingress Class         kubectl get ingress -o yaml           CLASS = nginx
App Pods              kubectl get pods -l app=...           All in Running state
App Service           kubectl describe svc spring-boot-...  Has endpoints (pod IPs)
DNS Resolution        nslookup myapp.haryana.com            Resolves to LB
HTTPS Certificate     kubectl get certificate               READY=True
App Accessibility     curl https://myapp.haryana.com        200 OK response
Browser Access        Open in browser                       Page loads with padlock ✅
```

---

## 🚀 Pre-Launch Checklist

Before declaring Ingress "ready":

```
[ ] EXTERNAL-IP is assigned (not pending)
[ ] EXTERNAL-IP is an AWS DNS name (starts with k8s-)
[ ] Ingress ADDRESS is populated
[ ] curl to LB DNS with Host header returns 200
[ ] HTTPS certificate shows READY=True
[ ] curl to HTTPS returns 200 without SSL warnings
[ ] DNS CNAME record points to load balancer
[ ] nslookup resolves domain correctly
[ ] Browser can access https://myapp.haryana.com
[ ] Padlock icon shows in browser
[ ] HTTP redirects to HTTPS
[ ] All health checks passing
[ ] No security group errors
[ ] No subnet resolution errors
```

---

## 🆘 When to Get Help

If you're stuck and nothing works:

1. **Check the logs:**
   ```bash
   kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
   kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
   kubectl logs -n cert-manager -l app=cert-manager
   ```

2. **Describe resources:**
   ```bash
   kubectl describe svc ingress-nginx-controller -n ingress-nginx
   kubectl describe ingress spring-boot-ingress
   kubectl describe pod spring-boot-kubernetes-abc123
   ```

3. **Check events:**
   ```bash
   kubectl get events --sort-by='.lastTimestamp' | tail -20
   kubectl get events -n ingress-nginx
   ```

4. **Check AWS resources:**
   ```bash
   # View load balancer in AWS Console
   # EC2 > Load Balancers > Find your NLB
   
   # Check security groups
   aws ec2 describe-security-groups \
     --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned"
   
   # Check subnets
   aws ec2 describe-subnets --query 'Subnets[*].[SubnetId,Tags]'
   ```

5. **Create a GitHub issue** with:
   - kubectl get ingress, svc, pods output
   - Controller logs (kubectl logs ...)
   - Error messages you're seeing
   - What you've already tried

---

## ✅ Success Confirmation

When everything is working:

```
✅ curl -I https://myapp.haryana.com
   HTTP/2 200 OK

✅ Browser shows https://myapp.haryana.com with padlock icon

✅ kubectl get svc -n ingress-nginx
   EXTERNAL-IP: k8s-ingressn-7ddea...elb.amazonaws.com

✅ kubectl get ingress
   ADDRESS: k8s-ingressn-7ddea...elb.amazonaws.com

✅ kubectl get certificate
   READY: True

Ingress is fully functional! 🎉
```
