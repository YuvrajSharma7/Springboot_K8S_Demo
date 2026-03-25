# 🚀 Cluster Autoscaler: Automatic Node Scaling for EKS

## Overview

To complete your enterprise-grade EKS setup, we will implement the **Cluster Autoscaler**. While the Horizontal Pod Autoscaler (HPA) adds more Pods when your app is busy, the Cluster Autoscaler adds more EC2 instances (Nodes) to your cluster when those Pods have nowhere to run.

This creates a seamless auto-scaling experience:
- 📈 **Tier 1 (HPA):** Scales your application Pods based on CPU/memory
- 🖥️ **Tier 2 (Cluster Autoscaler):** Scales your EKS cluster nodes based on Pod demand
- 💰 **Cost Efficient:** Scales down nodes when demand decreases

---

## Architecture: The Two-Tier Scaling System

```
High Demand Period:
┌─────────────────────────────────────────────────────────┐
│ 1. More user traffic detected                           │
│ 2. HPA creates 10 new Spring Boot Pods                  │
│ 3. Node 1 is full (no more CPU/Memory available)        │
│ 4. New Pods are in "Pending" state                      │
│ 5. Cluster Autoscaler detects pending Pods              │
│ 6. Cluster Autoscaler provisions a new EC2 Node 2       │
│ 7. New Pods are scheduled on Node 2                     │
│ 8. All Pods are now Running ✅                          │
└─────────────────────────────────────────────────────────┘

Low Demand Period:
┌─────────────────────────────────────────────────────────┐
│ 1. Traffic decreases                                    │
│ 2. HPA removes unnecessary Pods                         │
│ 3. Node 2 becomes empty (no Pods scheduled)             │
│ 4. Cluster Autoscaler detects unused node               │
│ 5. After 10 minutes, Cluster Autoscaler terminates Node 2
│ 6. Cost savings! 💰                                     │
└─────────────────────────────��───────────────────────────┘
```

---

## Prerequisites

Before starting, ensure you have:

- An EKS cluster with at least one Node Group
- AWS IAM permissions to modify role policies
- Helm 3.x installed
- `kubectl` configured to access your cluster
- AWS CLI configured with credentials

---

## Step 1: Understand the Permissions Required

For the Cluster Autoscaler to work, your **EKS Node IAM Role** needs permission to interact with AWS Auto Scaling Groups (ASG).

### 1.1 Find Your EKS Node IAM Role

First, identify which IAM role is used by your EKS nodes:

```bash
# Get your cluster name
CLUSTER_NAME="your-cluster-name"

# Get the Node Group name
NODE_GROUP_NAME=$(aws eks list-nodegroups --cluster-name $CLUSTER_NAME --query 'nodegroups[0]' --output text)

# Get the IAM role ARN
aws eks describe-nodegroup \
  --cluster-name $CLUSTER_NAME \
  --nodegroup-name $NODE_GROUP_NAME \
  --query 'nodegroup.nodeRole' \
  --output text

# Example output: arn:aws:iam::123456789012:role/eks-node-role-xyz
```

Note down your **Node IAM Role ARN**.

---

## Step 2: Add AWS Permissions to Node IAM Role

The Cluster Autoscaler needs specific permissions to manage Auto Scaling Groups. Add this inline policy to your Node IAM Role.

### 2.1 Create the Inline Policy

In the AWS Console:

1. Go to **IAM** > **Roles**
2. Search for and select your **EKS Node IAM Role**
3. Click **Add inline policy**
4. Choose **JSON** tab
5. Paste the following policy:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:DescribeAutoScalingInstances",
                "autoscaling:DescribeLaunchConfigurations",
                "autoscaling:DescribeTags",
                "autoscaling:SetDesiredCapacity",
                "autoscaling:TerminateInstanceInAutoScalingGroup",
                "ec2:DescribeLaunchTemplateVersions"
            ],
            "Resource": "*",
            "Effect": "Allow"
        }
    ]
}
```

### 2.2 Policy Permissions Explained

| Permission | Purpose |
|-----------|---------|
| `DescribeAutoScalingGroups` | Read ASG details (capacity, size) |
| `DescribeAutoScalingInstances` | Check which instances belong to ASG |
| `DescribeLaunchConfigurations` | Get instance configuration details |
| `DescribeTags` | Read tags on ASG (to find EKS groups) |
| `SetDesiredCapacity` | **Scale up nodes** when needed |
| `TerminateInstanceInAutoScalingGroup` | **Scale down nodes** when not needed |
| `DescribeLaunchTemplateVersions` | Support for modern launch templates |

### 2.3 Verify the Policy (Optional)

Alternatively, use AWS CLI:

```bash
ROLE_NAME="eks-node-role-xyz"  # Replace with your actual role name

# Create the policy
aws iam put-role-policy \
  --role-name $ROLE_NAME \
  --policy-name ClusterAutoscalerPolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:DescribeAutoScalingInstances",
                "autoscaling:DescribeLaunchConfigurations",
                "autoscaling:DescribeTags",
                "autoscaling:SetDesiredCapacity",
                "autoscaling:TerminateInstanceInAutoScalingGroup",
                "ec2:DescribeLaunchTemplateVersions"
            ],
            "Resource": "*",
            "Effect": "Allow"
        }
    ]
}'

# Verify the policy was added
aws iam get-role-policy --role-name $ROLE_NAME --policy-name ClusterAutoscalerPolicy
```

---

## Step 3: Deploy the Cluster Autoscaler via Helm

Now that permissions are set, deploy the Cluster Autoscaler using Helm.

### 3.1 Add the Autoscaler Helm Repository

```bash
# Add the Kubernetes autoscaler repository
helm repo add autoscaler https://kubernetes.github.io/autoscaler

# Update Helm repositories
helm repo update
```

### 3.2 Install the Cluster Autoscaler

Replace `<your-cluster-name>` and `<your-aws-region>` with your actual values:

```bash
# Set your configuration
CLUSTER_NAME="your-cluster-name"        # e.g., "spring-boot-eks-cluster"
AWS_REGION="ap-south-1"                 # e.g., "us-east-1", "eu-west-1"

# Install Cluster Autoscaler
helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName=$CLUSTER_NAME \
  --set awsRegion=$AWS_REGION \
  --set rbac.create=true \
  --set rbac.serviceAccount.create=true
```

### 3.3 Understanding the Installation Parameters

| Parameter | Purpose | Example |
|-----------|---------|---------|
| `--namespace kube-system` | Install in the system namespace | Standard for cluster services |
| `autoDiscovery.clusterName` | Auto-discover ASGs by cluster name | `spring-boot-eks-cluster` |
| `awsRegion` | AWS region for your cluster | `us-east-1`, `ap-south-1` |
| `rbac.create` | Create RBAC rules for the autoscaler | `true` |
| `rbac.serviceAccount.create` | Create a service account | `true` |

### 3.4 Verify the Installation

Check that the Cluster Autoscaler pod is running:

```bash
# List pods in kube-system namespace
kubectl get pods -n kube-system | grep cluster-autoscaler

# Expected output:
# cluster-autoscaler-xyz1a2b3c   1/1   Running   0   2m
```

Check the logs to ensure it started correctly:

```bash
# Get the pod name
POD_NAME=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler -o jsonpath='{.items[0].metadata.name}')

# View the logs
kubectl logs -n kube-system $POD_NAME

# You should see messages like:
# I0325 10:30:45.123456       1 cluster_autoscaler.go:115] Cluster Autoscaler v1.27.0
# I0325 10:30:45.456789       1 aws_manager.go:123] Discovered 1 ASG nodes
```

---

## Step 4: Tag Your Auto Scaling Group

The Cluster Autoscaler uses AWS tags to identify which Auto Scaling Groups it should manage. Proper tagging is **critical** for the autoscaler to work.

### 4.1 Find Your Auto Scaling Group

```bash
# List all Auto Scaling Groups
aws autoscaling describe-auto-scaling-groups \
  --query 'AutoScalingGroups[*].[AutoScalingGroupName,Tags[?Key==`kubernetes.io/cluster/`]]' \
  --output table

# Or, more simply, look for groups with your cluster name
aws autoscaling describe-auto-scaling-groups \
  --query "AutoScalingGroups[?contains(AutoScalingGroupName, '$CLUSTER_NAME')].[AutoScalingGroupName]" \
  --output text
```

Example output:
```
eks-spring-boot-cluster-node-group-20250325-abcd1234
```

### 4.2 Add Required Tags

Your ASG must have these two tags:

| Tag Key | Tag Value | Purpose |
|---------|-----------|---------|
| `k8s.io/cluster-autoscaler/enabled` | `true` | Enable autoscaling on this group |
| `k8s.io/cluster-autoscaler/<cluster-name>` | `owned` | Mark this ASG as owned by your cluster |

### 4.3 Apply Tags Using AWS Console

1. Go to **EC2** > **Auto Scaling Groups**
2. Find your ASG (name contains your cluster name)
3. Click on the ASG name
4. Go to **Tags** tab
5. Click **Manage tags**
6. Add these tags:
   - **Key:** `k8s.io/cluster-autoscaler/enabled` → **Value:** `true`
   - **Key:** `k8s.io/cluster-autoscaler/spring-boot-eks-cluster` → **Value:** `owned`
7. Click **Create tags**

### 4.4 Apply Tags Using AWS CLI

```bash
ASG_NAME="eks-spring-boot-cluster-node-group-20250325-abcd1234"
CLUSTER_NAME="spring-boot-eks-cluster"

# Add the enabled tag
aws autoscaling create-or-update-tags \
  --tags "ResourceId=$ASG_NAME,ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/enabled,Value=true,PropagateAtLaunch=false"

# Add the owned tag
aws autoscaling create-or-update-tags \
  --tags "ResourceId=$ASG_NAME,ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/$CLUSTER_NAME,Value=owned,PropagateAtLaunch=false"

# Verify tags were added
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --query 'AutoScalingGroups[0].Tags' \
  --output table
```

### 4.5 Verify Tag Configuration

```bash
# Check that Cluster Autoscaler found your ASG
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler | grep "Discovered"

# You should see output like:
# I0325 10:30:45.789123       1 aws_manager.go:145] Discovered ASG: eks-spring-boot-cluster-node-group-20250325-abcd1234 (min: 2, max: 10)
```

---

## Step 5: Configure HPA (Horizontal Pod Autoscaler)

The Cluster Autoscaler works best with HPA. Create an HPA for your Spring Boot deployment.

### 5.1 Create HPA Resource (k8s/hpa.yaml)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: spring-boot-hpa
  namespace: default
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: spring-boot-kubernetes
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30
```

### 5.2 HPA Configuration Explained

| Parameter | Purpose | Value |
|-----------|---------|-------|
| `minReplicas` | Minimum Pods always running | `2` |
| `maxReplicas` | Maximum Pods allowed | `10` |
| `cpu averageUtilization` | Target CPU percentage | `70%` |
| `memory averageUtilization` | Target memory percentage | `80%` |
| `scaleUp.periodSeconds` | How quickly to scale up | `30s` (aggressive) |
| `scaleDown.periodSeconds` | How quickly to scale down | `60s` (conservative) |

### 5.3 Deploy the HPA

```bash
# Apply the HPA
kubectl apply -f k8s/hpa.yaml

# Verify HPA is created
kubectl get hpa

# Expected output:
# NAME                REFERENCE                        TARGETS          MINPODS   MAXPODS   REPLICAS   AGE
# spring-boot-hpa     Deployment/spring-boot-kubernetes   45%/70%, 60%/80%   2         10        2          1m

# Watch HPA in real-time
kubectl get hpa -w
```

---

## Step 6: Test the Auto-Scaling

### 6.1 Generate Load to Trigger Scaling

Install and run a load testing tool:

```bash
# Create a test Pod
kubectl run -it load-generator --image=busybox /bin/sh

# Inside the Pod, generate requests
while true; do wget -q -O- http://spring-boot-kubernetes-service:8080; done
```

### 6.2 Monitor Scaling Events

In another terminal, watch the scaling in action:

```bash
# Terminal 1: Watch HPA status
kubectl get hpa -w

# Terminal 2: Watch Pods being created
kubectl get pods -w

# Terminal 3: Watch Nodes being added
kubectl get nodes -w

# Terminal 4: View Cluster Autoscaler logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler -f
```

### 6.3 Expected Scaling Sequence

```
Time 0s:  2 Pods running on 1 Node
Time 30s: CPU usage increases to 75%
Time 60s: HPA scales to 5 Pods (target: 70% CPU)
          Node 1 is now at 95% capacity
Time 90s: Cluster Autoscaler detects pending Pods
          AWS provisions new EC2 node (Node 2)
Time 120s: 2 Pods scheduled on Node 2
           All Pods are now Running ✅
```

### 6.4 Stop the Load Test

```bash
# Press Ctrl+C in the load-generator Pod
exit

# Delete the test Pod
kubectl delete pod load-generator
```

---

## 📊 Monitoring Cluster Autoscaler

### 7.1 Check Autoscaler Status

```bash
# Get recent scaling events
kubectl describe nodes

# View autoscaler logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler --tail=50

# Check HPA status
kubectl describe hpa spring-boot-hpa
```

### 7.2 View Scaling Metrics

```bash
# Get current node count
kubectl get nodes -o wide

# Get current Pod count
kubectl get pods --all-namespaces

# Get resource usage
kubectl top nodes
kubectl top pods
```

---

## 📁 Updated Repository Structure

Your `k8s/` folder should now include:

```
k8s/
├── deployment.yaml              # Spring Boot deployment
├── service.yaml                 # Service (with metrics port)
├── ingress.yaml                 # NGINX Ingress
├── issuer.yaml                  # Cert-Manager ClusterIssuer
├── service-monitor.yaml         # Prometheus ServiceMonitor
├── prometheus-alert.yaml        # Alert rules
└── hpa.yaml                      # Horizontal Pod Autoscaler
```

Add to Git and commit:

```bash
git add k8s/hpa.yaml
git commit -m "Add Horizontal Pod Autoscaler for automatic scaling"
git push origin main
```

---

## 🚨 Troubleshooting Cluster Autoscaler

### Issue: Pods Stay in "Pending" State

**Diagnosis:**
```bash
# Check Pod status
kubectl describe pod <pod-name>

# Look for events mentioning "Insufficient resources"
```

**Solution:**
1. Verify tags on ASG:
   ```bash
   aws autoscaling describe-auto-scaling-groups \
     --auto-scaling-group-names $ASG_NAME \
     --query 'AutoScalingGroups[0].Tags'
   ```

2. Verify autoscaler sees the ASG:
   ```bash
   kubectl logs -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler | grep "Discovered"
   ```

3. Check IAM permissions are correct

### Issue: Nodes Not Scaling Down

**Reason:** Nodes might have:
- Pods with local storage
- System pods that don't tolerate eviction
- PodDisruptionBudgets preventing shutdown

**Solution:**
```bash
# Check which Pods prevent scale-down
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler | grep "cannot remove node"

# Identify blocking Pods
kubectl get pods --all-namespaces -o json | jq '.items[] | select(.spec.volumes[]?.emptyDir != null) | .metadata.name'
```

### Issue: Cluster Autoscaler Pod Crashing

**Solution:**
1. Check logs for errors:
   ```bash
   kubectl logs -n kube-system <autoscaler-pod-name>
   ```

2. Common causes:
   - Invalid cluster name in Helm values
   - Missing AWS credentials
   - Insufficient IAM permissions

3. Reinstall if needed:
   ```bash
   helm uninstall cluster-autoscaler -n kube-system
   helm install cluster-autoscaler autoscaler/cluster-autoscaler \
     --namespace kube-system \
     --set autoDiscovery.clusterName=$CLUSTER_NAME \
     --set awsRegion=$AWS_REGION \
     --set rbac.create=true
   ```

---

## 🎯 Best Practices for Cluster Autoscaling

### 1. Set Appropriate Limits
```yaml
minReplicas: 2      # Always have at least 2 Pods for HA
maxReplicas: 20     # Prevent runaway scaling costs
```

### 2. Configure Resource Requests and Limits
```yaml
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1024Mi
```

**Why:** Autoscaler uses these to calculate Pod placement.

### 3. Use PodDisruptionBudgets
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: spring-boot-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: spring-boot-kubernetes
```

This ensures at least 1 Pod stays running during scale-down.

### 4. Monitor Scaling Metrics

Create a Grafana dashboard with:
- Number of nodes over time
- Number of Pods over time
- CPU utilization
- Pending Pods count

### 5. Set Realistic Max Nodes

```bash
# Calculate based on your needs
# If each Pod needs 500m CPU and node has 2 CPU:
# Each node can hold 4 Pods
# If maxReplicas=20, need minimum 5 nodes max

# Set in ASG:
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name $ASG_NAME \
  --max-size 15
```

---

## 📈 Scaling Performance Tips

### 1. Scale Up Aggressively
```yaml
scaleUp:
  stabilizationWindowSeconds: 0
  policies:
  - type: Percent
    value: 100      # Double the Pods if needed
    periodSeconds: 30
```

### 2. Scale Down Conservatively
```yaml
scaleDown:
  stabilizationWindowSeconds: 300  # Wait 5 minutes
  policies:
  - type: Percent
    value: 50       # Remove only 50% of Pods
    periodSeconds: 60
```

### 3. Use Multiple Metrics

Monitor both CPU and memory:
```yaml
metrics:
- type: Resource
  resource:
    name: cpu
    target:
      type: Utilization
      averageUtilization: 70
- type: Resource
  resource:
    name: memory
    target:
      type: Utilization
      averageUtilization: 80
```

---

## 📁 Complete Kubernetes Manifests

Create a comprehensive autoscaling setup:

```bash
# k8s directory structure
k8s/
├── deployment.yaml          # With proper resource requests/limits
├── service.yaml
├── ingress.yaml
├── hpa.yaml                 # Horizontal Pod Autoscaler
└── pod-disruption-budget.yaml  # Protect Pods during scale-down
```

---

## ✅ Cluster Autoscaler Verification Checklist

Before considering setup complete, verify:

- [ ] IAM policy added to Node role with all required permissions
- [ ] Cluster Autoscaler pod running in kube-system namespace
- [ ] ASG tagged with `k8s.io/cluster-autoscaler/enabled=true`
- [ ] ASG tagged with `k8s.io/cluster-autoscaler/<cluster-name>=owned`
- [ ] Autoscaler logs show "Discovered ASG" message
- [ ] HPA deployed for Spring Boot application
- [ ] Resource requests/limits set on all Pods
- [ ] Load test triggers Pod scaling (HPA)
- [ ] Pending Pods trigger node scaling (Cluster Autoscaler)
- [ ] Nodes scale down after 10+ minutes of low utilization

---

## 📈 Cost Savings Example

**Scenario:** Your Spring Boot app has variable traffic

```
Without Autoscaling:
- Always run 10 nodes (even at night)
- Cost: 10 × $0.50/hour = $5/hour = $3,650/month

With Autoscaling:
- Peak hours (8am-8pm): Run 10 nodes
- Off-peak (8pm-8am): Run 2 nodes
- Average: 6 nodes
- Cost: 6 × $0.50/hour = $3/hour = $2,190/month
- Savings: $1,460/month (40% reduction!) 💰
```

---

## 🔗 Useful Resources

- [Cluster Autoscaler on GitHub](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler)
- [AWS EKS Autoscaling Guide](https://docs.aws.amazon.com/eks/latest/userguide/autoscaling.html)
- [Kubernetes HPA Documentation](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [HPA Behavior Configuration](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#scaling-policies)

---

## 🎉 Summary

Your enterprise-grade auto-scaling infrastructure now includes:

1. ✅ **HPA:** Automatically scales Pods (1-10) based on CPU/memory
2. ✅ **Cluster Autoscaler:** Automatically scales nodes (EC2 instances) based on Pod demand
3. ✅ **Cost Optimization:** Scales down unused nodes to save money
4. ✅ **High Availability:** Maintains minimum replicas for reliability
5. ✅ **Production Ready:** Can handle traffic spikes without manual intervention

**Your application can now handle traffic spikes automatically while optimizing costs!** 🚀📈
