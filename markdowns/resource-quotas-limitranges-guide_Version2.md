# 🛡️ Resource Quotas and LimitRanges: Protecting Your EKS Cluster

## Overview

Setting up **Resource Quotas** and **LimitRanges** is the final layer of protection for your EKS cluster. Without them, a single "buggy" Spring Boot application with a memory leak could consume all the RAM on a worker node, causing critical system pods (like the Ingress Controller or CoreDNS) to crash.

Think of it as setting a **"budget"** for each application and team:
- 🎯 **Per-Pod Limits:** Prevent individual pods from hogging resources
- 📊 **Per-Namespace Quotas:** Prevent teams from exceeding their share
- 🚨 **Automatic Eviction:** Misbehaving pods are restarted, not allowed to crash the cluster
- 💰 **Cost Control:** Prevent accidental resource waste

---

## Architecture: Resource Management Layers

```
┌─────────────────────────────────────────────────────────────┐
│ Cluster Level (All Namespaces)                              │
│ - Total CPU across all nodes: 8 cores (2 nodes × 4 cores)   │
│ - Total Memory across all nodes: 32GB (2 nodes × 16GB)      │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Namespace Level (ResourceQuota)                             │
│ - Team allocation: 4 CPU cores, 8GB RAM                     │
│ - Protects against one team hogging everything              │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Pod Level (LimitRange + Container Resources)                │
│ - Per-pod limit: 1 CPU core, 1GB RAM                        │
│ - Per-pod request: 250m CPU, 512MB RAM                      │
│ - Protects against individual buggy pods                    │
└─────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

Before starting, ensure you have:

- An EKS cluster with nodes already running
- `kubectl` configured to access your cluster
- Understanding of Kubernetes resource units:
  - **CPU:** `1` = 1 CPU core, `500m` = half a core, `250m` = quarter core
  - **Memory:** `1Gi` = 1 Gigabyte, `512Mi` = 512 Megabytes

---

## Part 1: Understanding Requests vs. Limits

This is the foundation of resource management. Let's break it down:

### 1.1 Requests

**Definition:** The minimum guaranteed amount of resources a container needs to start.

**Kubernetes uses this to:**
- Decide which node to place the Pod on
- Schedule new Pods only if the node has enough available resources
- Perform fair resource distribution

**Example:**
```
Pod requests 250m CPU
Node has 2000m CPU available
Kubernetes schedules the Pod ✅
```

### 1.2 Limits

**Definition:** The maximum amount of resources a container is allowed to use.

**Enforcement:**
- **CPU Limit exceeded:** Container gets throttled (slowed down). Requests continue but slower.
- **Memory Limit exceeded:** Container gets OOMKilled (restarted immediately).

**Example:**
```
Pod requests 250m CPU, limits 500m CPU
During peak load, Pod tries to use 700m CPU
Kubernetes throttles it to 500m (not restarted)

Pod requests 512Mi memory, limits 1Gi memory
Pod's memory leak reaches 1.5Gi
Kubernetes OOMKills the Pod (restarts it)
```

### 1.3 The Request/Limit Ratio

Best practice guidelines:

| Application Type | Request | Limit | Ratio |
|-----------------|---------|-------|-------|
| **Light (API)** | 100m CPU, 256Mi mem | 200m CPU, 512Mi mem | 1:2 |
| **Standard (Spring Boot)** | 250m CPU, 512Mi mem | 500m CPU, 1Gi mem | 1:2 |
| **Heavy (Processing)** | 500m CPU, 1Gi mem | 1000m CPU, 2Gi mem | 1:2 |
| **Very Heavy (ML)** | 1000m CPU, 2Gi mem | 2000m CPU, 4Gi mem | 1:2 |

**Rule of thumb:** Set limits to roughly **2x the request** to allow for traffic spikes while maintaining fairness.

---

## Part 2: Update Deployment with Resource Requests and Limits

### 2.1 Understanding Your Spring Boot App

Before setting resources, determine your app's typical needs:

```bash
# If already running, check current resource usage
kubectl top pods

# Check CPU and memory from monitoring
# In Grafana, look at these metrics:
# - jvm_memory_used_bytes
# - jvm_memory_max_bytes
# - process_cpu_time_seconds_total
```

### 2.2 Update k8s/deployment.yaml

Add the `resources` block to your container specification:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-boot-kubernetes
  labels:
    app: spring-boot-kubernetes
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
        image: <your-ecr-repo>/spring-boot-kubernetes:latest
        ports:
        - containerPort: 8080
          name: http
        - containerPort: 9090
          name: metrics
        
        # ADD THIS SECTION FOR RESOURCE MANAGEMENT
        resources:
          requests:
            memory: "512Mi"      # Minimum guaranteed memory
            cpu: "250m"          # Minimum guaranteed CPU (1/4 core)
          limits:
            memory: "1Gi"        # Maximum allowed memory
            cpu: "500m"          # Maximum allowed CPU (1/2 core)
        
        # Health checks (recommended with resource limits)
        livenessProbe:
          httpGet:
            path: /actuator/health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        
        readinessProbe:
          httpGet:
            path: /actuator/health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
```

### 2.3 Resource Recommendations by Spring Boot App Type

#### Lightweight API Service
```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "200m"
```

#### Standard REST API (your baseline)
```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "500m"
```

#### Data Processing Service
```yaml
resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "1000m"
```

#### Memory-Intensive Cache Service
```yaml
resources:
  requests:
    memory: "2Gi"
    cpu: "1000m"
  limits:
    memory: "4Gi"
    cpu: "2000m"
```

### 2.4 Apply the Updated Deployment

```bash
# Apply the updated deployment
kubectl apply -f k8s/deployment.yaml

# Verify the pods restarted with new resource limits
kubectl get pods

# Check resource requests on running pods
kubectl describe pod <pod-name>

# Should show:
# Limits:
#   cpu:                500m
#   memory:             1Gi
# Requests:
#   cpu:                250m
#   memory:             512Mi
```

---

## Part 3: Set Namespace-Level ResourceQuota

If you have multiple teams using the cluster, you can set a **ResourceQuota** on the entire namespace to prevent one team from accidentally spinning up 100 expensive pods.

### 3.1 Create the ResourceQuota (k8s/quota.yaml)

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-haryana-quota
  namespace: default
spec:
  hard:
    # Pod count limits
    pods: "20"                          # Max 20 pods in this namespace
    
    # CPU limits
    requests.cpu: "4"                   # Max 4 CPU cores of requests
    limits.cpu: "8"                     # Max 8 CPU cores of limits
    
    # Memory limits
    requests.memory: "8Gi"              # Max 8GB of requested memory
    limits.memory: "16Gi"               # Max 16GB of memory limits
    
    # Storage (if using persistent volumes)
    requests.storage: "100Gi"           # Max 100GB of storage requested
    persistentvolumeclaims: "5"         # Max 5 PVCs
```

### 3.2 Understanding ResourceQuota Fields

| Field | Purpose | Example |
|-------|---------|---------|
| `pods` | Maximum number of Pods | `20` (supports 20 pods max) |
| `requests.cpu` | Maximum sum of CPU requests | `4` (max 16 pods × 250m each) |
| `requests.memory` | Maximum sum of memory requests | `8Gi` (max 16 pods × 512Mi each) |
| `limits.cpu` | Maximum sum of CPU limits | `8` (2x the requests) |
| `limits.memory` | Maximum sum of memory limits | `16Gi` (2x the requests) |
| `requests.storage` | Max persistent volume requests | `100Gi` |
| `persistentvolumeclaims` | Max PVC count | `5` |

### 3.3 Multi-Team Example

If you have multiple teams in separate namespaces:

**Team A (Production):**
```yaml
metadata:
  name: quota-team-a
  namespace: team-a
spec:
  hard:
    pods: "50"
    requests.cpu: "10"
    requests.memory: "20Gi"
    limits.cpu: "20"
    limits.memory: "40Gi"
```

**Team B (Staging):**
```yaml
metadata:
  name: quota-team-b
  namespace: team-b
spec:
  hard:
    pods: "20"
    requests.cpu: "4"
    requests.memory: "8Gi"
    limits.cpu: "8"
    limits.memory: "16Gi"
```

### 3.4 Deploy the ResourceQuota

```bash
# Create the quota
kubectl apply -f k8s/quota.yaml

# View the quota
kubectl get resourcequota -n default

# Get detailed quota info
kubectl describe resourcequota team-haryana-quota -n default

# Expected output:
# Name:              team-haryana-quota
# Namespace:         default
# Resource           Used    Hard
# --------           ----    ----
# limits.cpu         500m    8
# limits.memory      1Gi     16Gi
# pods               2       20
# requests.cpu       500m    4
# requests.memory    1Gi     8Gi
```

---

## Part 4: Set Pod-Level LimitRange

A **LimitRange** enforces minimum and maximum resource constraints at the Pod level. It prevents users from:
- Creating Pods with no resource limits (dangerous!)
- Creating Pods requesting excessive resources (waste)
- Creating Pods with limits lower than requests (invalid)

### 4.1 Create the LimitRange (k8s/limitrange.yaml)

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: pod-limit-range
  namespace: default
spec:
  limits:
  # Container-level limits
  - type: Container
    min:
      cpu: "50m"                # Minimum CPU per container
      memory: "64Mi"            # Minimum memory per container
    max:
      cpu: "2"                  # Maximum CPU per container
      memory: "4Gi"             # Maximum memory per container
    default:
      cpu: "500m"               # Default limit if not specified
      memory: "512Mi"
    defaultRequest:
      cpu: "100m"               # Default request if not specified
      memory: "128Mi"
    
  # Pod-level limits (sum of all containers)
  - type: Pod
    min:
      cpu: "100m"               # Minimum total CPU per pod
      memory: "128Mi"           # Minimum total memory per pod
    max:
      cpu: "4"                  # Maximum total CPU per pod
      memory: "8Gi"             # Maximum total memory per pod
```

### 4.2 Understanding LimitRange Fields

| Type | Field | Purpose | Example |
|------|-------|---------|---------|
| Container | `min` | Minimum allowed per container | `cpu: 50m` |
| Container | `max` | Maximum allowed per container | `memory: 4Gi` |
| Container | `default` | Applied if no limit specified | `cpu: 500m` |
| Container | `defaultRequest` | Applied if no request specified | `memory: 128Mi` |
| Pod | `min` | Minimum for entire Pod | `cpu: 100m` |
| Pod | `max` | Maximum for entire Pod | `memory: 8Gi` |

### 4.3 Deploy the LimitRange

```bash
# Create the limit range
kubectl apply -f k8s/limitrange.yaml

# View the limit range
kubectl get limitrange -n default

# Get detailed info
kubectl describe limitrange pod-limit-range -n default
```

### 4.4 What Happens When You Violate Limits

**Example 1: Pod exceeds max limits**
```yaml
# This Pod violates the max limit (2 CPU)
resources:
  limits:
    cpu: "3"  # > 2 CPU limit!
```

**Error:**
```
Error from server (Forbidden): error when creating "deployment.yaml":
pods "spring-boot-xyz" is forbidden:
[cpu limit: 3 is greater than the maximum allowed 2]
```

**Example 2: Request > Limit**
```yaml
resources:
  requests:
    cpu: "1000m"
  limits:
    cpu: "500m"  # Request > Limit!
```

**Error:**
```
Error from server (Forbidden): error when creating "deployment.yaml":
requests.cpu: Invalid value: "1000m":
must be less than or equal to limit: "500m"
```

---

## Part 5: Monitoring Resource Usage

### 5.1 Check Current Resource Usage

```bash
# View resource usage for all Pods
kubectl top pods

# Example output:
# NAME                                     CPU(cores)   MEMORY(bytes)
# spring-boot-kubernetes-xyz1a2b3c         120m         450Mi
# spring-boot-kubernetes-xyz4d5e6f         140m         480Mi

# View resource usage by node
kubectl top nodes

# Example output:
# NAME                                    CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
# ip-10-0-1-100.compute.internal          1500m        75%    8Gi             50%
# ip-10-0-2-200.compute.internal          800m         40%    4Gi             25%
```

### 5.2 View ResourceQuota Status

```bash
# Check if you're close to quota limits
kubectl describe resourcequota team-haryana-quota

# Output shows:
# Resource           Used      Hard
# --------           ----      ----
# limits.cpu         1000m     8
# limits.memory      960Mi     16Gi
# pods               2         20
# requests.cpu       500m      4
# requests.memory    960Mi     8Gi
```

### 5.3 Create Grafana Dashboards for Resource Monitoring

Use these Prometheus queries in Grafana:

```promql
# Pod CPU usage percentage relative to request
(container_cpu_usage_seconds_total / on(pod) container_spec_cpu_quota) * 100

# Pod memory usage percentage relative to limit
(container_memory_usage_bytes / on(pod) container_spec_memory_limit_bytes) * 100

# Namespace CPU requests vs limit
sum(kube_pod_container_resource_requests_cpu_cores) by (namespace)

# Namespace memory requests vs limit
sum(kube_pod_container_resource_requests_memory_bytes) by (namespace)
```

---

## Part 6: Practical Examples & Common Scenarios

### 6.1 Scenario: Memory Leak Detection

**Problem:** Your Spring Boot app has a memory leak. Without limits, it crashes the node.

**Without Limits:**
```
Memory usage grows: 100MB → 500MB → 1GB → Node's 16GB full
CoreDNS crashes (no memory left)
Entire cluster becomes unstable 💥
```

**With Limits (1Gi):**
```
Memory usage grows: 100MB → 500MB → 1GB (hits limit)
Container gets OOMKilled and restarted ✅
Kubernetes automatically restarts the Pod
Other system pods remain healthy ✅
```

### 6.2 Scenario: Buggy Deployment Consuming All CPU

**Problem:** A buggy deployment spawns infinite threads.

**Without Limits:**
```
CPU usage: 1 core → 2 cores → 4 cores (all available)
Other Pods get starved
Service degrades for all customers 💥
```

**With Limits (500m):**
```
CPU usage: 100m → 300m → 500m (hits limit)
Container gets throttled (slowed down)
Service quality degrades but stays running ✅
Other Pods can still get CPU time ✅
```

### 6.3 Scenario: Team Accidentally Creates Too Many Pods

**Problem:** Junior developer accidentally creates 100 Pods.

**Without Quota:**
```
100 Pods × 512Mi = 51.2GB memory needed
Only 32GB available
Cluster runs out of memory
Unrelated services crash 💥
```

**With Quota (8Gi requests.memory):**
```
First 16 Pods created successfully
17th Pod creation fails:
"ResourceQuota exceeded: requests.memory 8Gi limit"
Developer is alerted immediately ✅
```

---

## Part 7: Resource Tuning Guidelines

### 7.1 Determine Request Values (Start Conservative)

1. **Check your monitoring:**
   ```bash
   kubectl top pods
   ```

2. **For Spring Boot apps, typical values are:**
   - Light API: 100m CPU, 256Mi memory
   - Standard REST: 250m CPU, 512Mi memory
   - Data processor: 500m CPU, 1Gi memory

3. **Formula:**
   ```
   Request = (95th percentile usage) + 20% headroom
   Limit = Request × 2 (to handle traffic spikes)
   ```

### 7.2 Set Request Values (Bottom-Up Approach)

```bash
# Step 1: Deploy without limits
kubectl apply -f deployment.yaml

# Step 2: Monitor for 1-2 hours during normal traffic
kubectl top pods -n default

# Step 3: Get 95th percentile values
# If seeing: CPU 150m, Memory 400Mi
# Set requests: CPU 200m, Memory 500Mi (add 20% headroom)
# Set limits: CPU 400m, Memory 1Gi (double the requests)
```

### 7.3 Iterative Tuning

```
Week 1: Initial estimate
↓
Week 2: Monitor Grafana → see if throttled
↓
Week 3: Adjust limits up if throttled, down if too generous
↓
Week 4: Stabilize at optimal values
```

---

## 📁 Complete Resource Management Setup

Your `k8s/` folder should now include:

```
k8s/
├── deployment.yaml              # WITH resource requests/limits
├── service.yaml
├── ingress.yaml
├── issuer.yaml
├── service-monitor.yaml
├── prometheus-alert.yaml
├── hpa.yaml
├── quota.yaml                   # ResourceQuota for namespace
└── limitrange.yaml              # LimitRange for pods
```

Apply all resources:

```bash
# Apply all resources in order
kubectl apply -f k8s/quota.yaml
kubectl apply -f k8s/limitrange.yaml
kubectl apply -f k8s/deployment.yaml

# Verify everything
kubectl get resourcequota,limitrange,pods
```

---

## 🚨 Troubleshooting Resource Issues

### Issue: Pod Won't Schedule - "Insufficient CPU"

**Diagnosis:**
```bash
kubectl describe pod <pod-name>
# Look for: "Insufficient cpu"
```

**Solution:**
1. Check available resources on nodes:
   ```bash
   kubectl top nodes
   ```

2. Check pod's request:
   ```bash
   kubectl describe pod <pod-name> | grep "Requests"
   ```

3. Either:
   - Reduce pod requests
   - Add more nodes
   - Scale down other pods

### Issue: Pod Gets OOMKilled

**Diagnosis:**
```bash
kubectl describe pod <pod-name>
# Look for: "OOMKilled" or "Exit Code: 137"
```

**Solution:**
1. Check current memory usage:
   ```bash
   kubectl top pods
   ```

2. Increase memory limit:
   ```yaml
   resources:
     limits:
       memory: "2Gi"  # Was 1Gi, now 2Gi
   ```

3. Deploy updated config:
   ```bash
   kubectl apply -f k8s/deployment.yaml
   ```

### Issue: Pod Gets Throttled (CPU)

**Diagnosis:**
```bash
# In Grafana, see container_throttled_periods increasing
```

**Solution:**
Increase CPU limit:
```yaml
resources:
  limits:
    cpu: "1000m"  # Was 500m, now 1000m
```

### Issue: ResourceQuota Prevents Pod Creation

**Error:**
```
Error from server (Forbidden):
ResourceQuota exceeded: requests.memory "8Gi" limit
```

**Solution:**
1. Reduce pod memory request:
   ```yaml
   resources:
     requests:
       memory: "256Mi"  # Was 512Mi
   ```

2. Or increase namespace quota:
   ```bash
   kubectl patch resourcequota team-haryana-quota \
     -p '{"spec":{"hard":{"requests.memory":"12Gi"}}}'
   ```

---

## ✅ Resource Management Verification Checklist

Before considering setup complete, verify:

- [ ] All Pods have `requests.cpu` and `requests.memory` defined
- [ ] All Pods have `limits.cpu` and `limits.memory` defined
- [ ] Request values are realistic (not arbitrary)
- [ ] Limit values are 1.5-2x the request values
- [ ] ResourceQuota created for your namespace
- [ ] `kubectl get resourcequota` shows your quota
- [ ] LimitRange created for your namespace
- [ ] `kubectl get limitrange` shows your limit range
- [ ] Pod can be created without errors
- [ ] ResourceQuota status shows used vs hard values
- [ ] HPA works with resource limits defined
- [ ] Cluster Autoscaler considers requests when scheduling

---

## 📊 Resource Planning Worksheet

Use this to document your settings:

```
Application Name: Spring Boot API
Team: Haryana

PER-POD SETTINGS:
├── CPU Request: 250m
├── CPU Limit: 500m
├── Memory Request: 512Mi
└── Memory Limit: 1Gi

NAMESPACE QUOTA (for 10 pods):
├── Max Pods: 20
├── Max CPU Requests: 4 cores (10 × 250m + buffer)
├── Max CPU Limits: 8 cores (10 × 500m + buffer)
├── Max Memory Requests: 8Gi (10 × 512Mi + buffer)
└── Max Memory Limits: 16Gi (10 × 1Gi + buffer)

REASONING:
├── Requests are based on 95th percentile monitoring
├── Limits allow 2x headroom for traffic spikes
├── Quota allows 2x the typical pod count
└── Updated: [Date] by [Person]
```

---

## 🎯 Best Practices Summary

### 1. Always Define Requests and Limits
```yaml
# ❌ DON'T DO THIS
resources: {}

# ✅ DO THIS
resources:
  requests:
    cpu: "250m"
    memory: "512Mi"
  limits:
    cpu: "500m"
    memory: "1Gi"
```

### 2. Keep Limits Reasonable
```yaml
# ❌ TOO LOOSE (defeats the purpose)
limits:
  cpu: "10"
  memory: "16Gi"

# ✅ REASONABLE
limits:
  cpu: "500m"
  memory: "1Gi"
```

### 3. Monitor and Adjust
```bash
# Weekly check
kubectl top pods
# If consistently using 90%+ of limits, increase them
# If using <20% of limits, decrease them (save costs)
```

### 4. Use Namespaces for Multi-Tenant Clusters
```yaml
# Each team gets their own namespace with quota
kind: Namespace
metadata:
  name: team-a
---
kind: ResourceQuota
metadata:
  name: team-a-quota
  namespace: team-a
spec:
  hard:
    requests.cpu: "10"
    requests.memory: "20Gi"
```

### 5. Combine with HPA and Cluster Autoscaler
```yaml
# HPA considers requests when scaling Pods
# Cluster Autoscaler considers requests when scaling nodes
# This ensures fair resource distribution across your cluster
```

---

## 🔗 Useful Resources

- [Kubernetes Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [ResourceQuota Documentation](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [LimitRange Documentation](https://kubernetes.io/docs/concepts/policy/limit-range/)
- [Kubernetes Units Explained](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/#resource-units-in-kubernetes)
- [Spring Boot Resource Tuning](https://spring.io/blog/2021/05/24/spring-boot-docker-service-resource-optimization)

---

## 🎉 Summary

Your enterprise-grade resource management setup now provides:

1. ✅ **Per-Pod Protection:** Resource requests/limits prevent individual pods from crashing the cluster
2. ✅ **Per-Namespace Fairness:** ResourceQuota ensures no single team monopolizes resources
3. ✅ **Automatic Enforcement:** LimitRange prevents invalid configurations
4. ✅ **Cost Optimization:** Accurate requests enable efficient scheduling
5. ✅ **Stability:** Memory leaks and CPU spikes are contained and managed
6. ✅ **Scalability:** HPA and Cluster Autoscaler work effectively with well-defined resources

**Your cluster is now production-ready with multi-team resource isolation and protection!** 🛡️✨
