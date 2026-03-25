# 🆘 Disaster Recovery with Velero: Complete Cluster Backup & Restore

## Overview

To truly complete your journey, we are moving into **Disaster Recovery (DR)**. Even the most perfectly tuned EKS cluster in `ap-south-1` (Mumbai) could face:
- 🔴 Regional AWS outage
- 💥 Catastrophic accidental deletion (`kubectl delete ns` on the wrong window)
- 🔐 Security breach requiring cluster recreation
- 🌪️ Unrecoverable data corruption

**Velero** is the industry standard for backing up and restoring Kubernetes cluster resources and persistent volumes.

With Velero, you get:
- ✅ **Full Cluster Backup:** All Kubernetes resources (Deployments, ConfigMaps, Secrets, Ingress)
- ✅ **Persistent Data:** EBS volume snapshots for stateful data
- ✅ **Automated Scheduling:** Nightly backups without manual intervention
- ✅ **Point-in-Time Recovery:** Restore from any previous backup
- ✅ **Cross-Region Disaster Recovery:** Backup in one region, restore in another
- ✅ **RTO/RPO Optimization:** Recovery Time Objective and Recovery Point Objective

---

## Architecture: How Velero Works

### The Backup Process

```
Your EKS Cluster (ap-south-1)
├── Kubernetes Metadata
│   ├── Deployments (spring-boot-kubernetes)
│   ├── Services (LoadBalancers, NodePorts)
│   ├── Ingress (NGINX controller)
│   ├── Secrets (DB credentials)
│   ├── ConfigMaps (application config)
│   └── PersistentVolumes (if using storage)
│
└── Persistent Data (EBS volumes)
    ├── PostgreSQL database
    └── Application cache volumes

        ↓ Velero Backup Process

Velero Agent (runs in cluster)
├── Queries Kubernetes API
├── Collects all YAML manifests
├── Creates EBS snapshots
├── Compresses everything
└── Uploads to S3 Bucket

        ↓

AWS S3 Bucket (haryana-eks-backups)
├── daily-backup-20250325-120000/
│   ├── cluster metadata (velero-resources.tar.gz)
│   ├── EBS snapshots (vol-1a2b3c4d, vol-5e6f7g8h)
│   ├── manifests.json
│   └── backup.json
├── daily-backup-20250326-010000/
└── daily-backup-20250327-010000/

        ↓ (stored safely, can restore anytime)
```

### The Restore Process

```
Disaster Strikes!
├── Original cluster deleted
├── All data gone
└── You have nightmares 😱

        ↓ (Don't panic, you have backups!)

New EKS Cluster Created (same or different region)
        ↓
Velero Installed & Configured
        ↓
velero restore create --from-backup daily-backup-20250325
        ↓
Velero Agent
├── Fetches backup from S3
├── Restores all Kubernetes resources
├── Restores EBS volumes from snapshots
├���─ Applies all configurations
└── Waits for workloads to become healthy

        ↓ (minutes later)

Everything is back! ✨
├── Deployments restarted
├── Argo CD syncing
├── Spring Boot app running
├── Ingress accepting traffic
├── SSL certificates restored
└── Your data intact
```

---

## Prerequisites

Before starting, ensure you have:

- An **existing EKS cluster** (production or staging)
- **AWS CLI** configured with credentials
- **kubectl** configured to access your cluster
- **Velero CLI** installed locally (or install via script)
- **S3 bucket creation** permissions in AWS
- **IAM role modification** permissions
- **EBS snapshot** permissions

---

## Part 1: Understanding Velero Concepts

### 1.1 Backup (Snapshot)

A **Backup** is a point-in-time snapshot of your entire cluster state.

```
backup: daily-backup-20250325-010000
├── taken at: 2025-03-25 01:00:00 UTC
├── includes: All cluster resources (100% fidelity)
├── includes: EBS snapshots for volumes
├── status: Completed (23 seconds)
└── size: 2.3 GB in S3
```

### 1.2 Schedule (Recurring Backup)

A **Schedule** creates backups automatically on a cron-like pattern.

```
schedule: daily-backup
├── cron: "0 1 * * *"        (every day at 1 AM UTC)
├── ttl: 720h                 (keep for 30 days)
├── retention: 5 backups      (keep last 5)
└── next run: 2025-03-26 01:00:00 UTC
```

### 1.3 Restore (Recovery)

A **Restore** recreates cluster resources from a backup.

```
restore: cluster-disaster-recovery
├── from-backup: daily-backup-20250325-010000
├── status: In Progress
├── restored: 45 resources
├── failed: 0 resources
└── eta: 2 minutes remaining
```

### 1.4 Backup Storage Location

Where backups are stored (S3, Azure, GCS, etc.)

```
storage location: default
├── provider: AWS
├── bucket: haryana-eks-backups
├── prefix: cluster1/
├── region: ap-south-1
└── encryption: enabled (server-side)
```

### 1.5 Volume Snapshot Location

Where EBS snapshots are stored.

```
snapshot location: default
├── provider: AWS
├── region: ap-south-1
└── encrypted: yes
```

---

## Part 2: Create S3 Bucket for Backups

### 2.1 Create S3 Bucket (AWS Console)

1. Go to **AWS S3 Console**
2. Click **Create Bucket**
3. Name: `haryana-eks-backups`
4. Region: Same as EKS cluster (`ap-south-1`)
5. Enable **Versioning** (recommended)
6. Enable **Server-side encryption** (recommended)
7. Block public access (leave all checked)
8. Create bucket

### 2.2 Create S3 Bucket (AWS CLI)

```bash
# Set variables
BUCKET_NAME="haryana-eks-backups"
AWS_REGION="ap-south-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create bucket
aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --region $AWS_REGION \
  --create-bucket-configuration LocationConstraint=$AWS_REGION

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled

# Enable server-side encryption
aws s3api put-bucket-encryption \
  --bucket $BUCKET_NAME \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Verify bucket
aws s3api head-bucket --bucket $BUCKET_NAME
echo "✅ Bucket created: s3://$BUCKET_NAME"
```

### 2.3 Create IAM Role for Velero

Velero needs permissions to access S3 and create EBS snapshots.

**Create IAM Policy (velero-policy.json):**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeVolumes",
        "ec2:DescribeSnapshots",
        "ec2:CreateTags",
        "ec2:CreateSnapshot",
        "ec2:DeleteSnapshot"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:PutObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": "arn:aws:s3:::haryana-eks-backups/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::haryana-eks-backups"
    }
  ]
}
```

**Create IAM User and Attach Policy:**

```bash
# Create IAM user for Velero
VELERO_USER="velero-backup-user"
aws iam create-user --user-name $VELERO_USER

# Create access key
VELERO_CREDENTIALS=$(aws iam create-access-key --user-name $VELERO_USER)
AWS_ACCESS_KEY_ID=$(echo $VELERO_CREDENTIALS | jq -r '.AccessKey.AccessKeyId')
AWS_SECRET_ACCESS_KEY=$(echo $VELERO_CREDENTIALS | jq -r '.AccessKey.SecretAccessKey')

# Create and attach policy
aws iam put-user-policy \
  --user-name $VELERO_USER \
  --policy-name velero-backup-policy \
  --policy-document file://velero-policy.json

# Save credentials for Velero installation
cat > credentials-velero <<EOF
[default]
aws_access_key_id=$AWS_ACCESS_KEY_ID
aws_secret_access_key=$AWS_SECRET_ACCESS_KEY
EOF

# Verify credentials file
cat credentials-velero
```

**⚠️ Security Note:** Keep `credentials-velero` safe. Delete it after Velero installation.

---

## Part 3: Install Velero CLI

### 3.1 Install Velero CLI Locally

**On macOS:**
```bash
# Using Homebrew
brew install velero

# Verify installation
velero version
# Output: Client version: v1.13.0
```

**On Linux:**
```bash
# Download latest release
wget https://github.com/vmware-tanzu/velero/releases/download/v1.13.0/velero-v1.13.0-linux-amd64.tar.gz

# Extract and install
tar -xzf velero-v1.13.0-linux-amd64.tar.gz
sudo mv velero-v1.13.0-linux-amd64/velero /usr/local/bin/

# Verify installation
velero version
```

**On Windows:**
```powershell
# Using Chocolatey
choco install velero

# Or download from releases and add to PATH
# https://github.com/vmware-tanzu/velero/releases
```

### 3.2 Verify Velero Installation

```bash
# Check version
velero version --client-only

# Check Velero documentation
velero --help
```

---

## Part 4: Install Velero Server in EKS Cluster

### 4.1 Install Velero with AWS Plugin

```bash
# Set variables
CLUSTER_NAME="spring-boot-eks-cluster"
BUCKET_NAME="haryana-eks-backups"
AWS_REGION="ap-south-1"

# Install Velero in the cluster
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.9.0 \
  --bucket $BUCKET_NAME \
  --backup-location-config region=$AWS_REGION \
  --snapshot-location-config region=$AWS_REGION \
  --secret-file ./credentials-velero \
  --wait

# Verify installation
kubectl get ns velero
kubectl get pods -n velero
```

**Expected output:**
```
velero                     Active   2m
NAME                                      READY   STATUS    RESTARTS   AGE
velero-7b8c9d1e2f3g4h5i               1/1     Running   0          1m
node-agent-xyz1a2b3c4d5e6f           1/1     Running   0          1m
```

### 4.2 Verify Velero Configuration

```bash
# Get backup storage locations
kubectl get backupstoragelocation -n velero

# Expected output:
# NAME      PROVIDER   BUCKET/CONTAINER        PHASE       LAST VALIDATED
# default   aws        haryana-eks-backups     Available   2m ago

# Get volume snapshot locations
kubectl get volumesnapshotlocation -n velero

# Expected output:
# NAME      PROVIDER   PHASE       LAST VALIDATED
# default   aws        Available   2m ago

# Describe the backup storage location
kubectl describe backupstoragelocation default -n velero
```

### 4.3 Secure and Clean Up Credentials File

```bash
# After Velero is installed, securely delete the credentials file
# (Velero already has them stored in a Kubernetes Secret)
shred -vfz credentials-velero
rm -f credentials-velero

# Verify credentials are stored in cluster
kubectl get secret -n velero
# Look for: cloud-credentials or similar
```

---

## Part 5: Create Backup Schedules

### 5.1 Create Daily Backup Schedule

```bash
# Create a schedule that backs up every day at 1 AM UTC
# and keeps backups for 30 days (720 hours)
velero schedule create daily-backup \
  --schedule="0 1 * * *" \
  --ttl 720h0m0s

# Verify schedule
velero schedule get

# Expected output:
# NAME           STATUS      SCHEDULE    BACKUP TTL   LAST BACKUP   SELECTOR
# daily-backup   Enabled     0 1 * * *   720h0m0s     N/A           <none>

# Describe schedule
velero schedule describe daily-backup
```

### 5.2 Create Hourly Backup Schedule (Optional)

```bash
# Backup every hour (more frequent recovery points)
velero schedule create hourly-backup \
  --schedule="0 * * * *" \
  --ttl 360h0m0s  # Keep for 15 days

# Verify both schedules
velero schedule get
```

### 5.3 Understand Cron Expressions

```
Format: minute hour day-of-month month day-of-week
        0      1    *             *     *

Examples:
"0 1 * * *"      = Every day at 1:00 AM
"0 * * * *"      = Every hour at :00
"*/15 * * * *"   = Every 15 minutes
"0 2 * * 0"      = Every Sunday at 2:00 AM
"0 1 1 * *"      = First day of month at 1:00 AM
"0 1,13 * * *"   = Every day at 1:00 AM and 1:00 PM
```

### 5.4 Monitor Scheduled Backups

```bash
# Get all backups
velero backup get

# Expected output:
# NAME                          STATUS      ERRORS   WARNINGS   CREATED                         EXPIRES
# daily-backup-20250325-010000  Completed   0        0          2025-03-25 01:00:31 +0000 UTC  2025-04-24 01:00:31 +0000 UTC

# Describe a specific backup
velero backup describe daily-backup-20250325-010000 --details

# View backup logs
velero backup logs daily-backup-20250325-010000 | head -50
```

---

## Part 6: Manual Backup Creation

### 6.1 Create On-Demand Backup

```bash
# Immediately backup the entire cluster
velero backup create manual-backup-$(date +%Y%m%d-%H%M%S)

# Example:
velero backup create manual-backup-20250325-143000

# Wait for backup to complete
velero backup get manual-backup-20250325-143000

# Watch progress
watch 'velero backup get manual-backup-20250325-143000'
```

### 6.2 Backup Specific Namespaces Only

```bash
# Backup only the default namespace
velero backup create backup-default-ns --include-namespaces default

# Backup multiple namespaces
velero backup create backup-production \
  --include-namespaces default,monitoring,kube-system

# Backup all except kube-system
velero backup create backup-apps \
  --exclude-namespaces kube-system,kube-public
```

### 6.3 Backup Specific Resource Types

```bash
# Backup only Deployments and Services
velero backup create backup-workloads \
  --include-resources deployments,services

# Backup everything except Secrets
velero backup create backup-no-secrets \
  --exclude-resources secrets

# Backup Ingress and Certificates only
velero backup create backup-networking \
  --include-resources ingresses,certificates
```

### 6.4 Check Backup Contents

```bash
# Get detailed backup information
velero backup describe daily-backup-20250325-010000 --details

# View backup contents (manifests)
velero backup logs daily-backup-20250325-010000 | grep "Backed up" | wc -l

# List all resources in backup
velero backup logs daily-backup-20250325-010000 | grep "resources"

# Export backup manifest
kubectl get backup daily-backup-20250325-010000 -n velero -o yaml
```

---

## Part 7: The "Big Red Button" - Restoring Your Cluster

### 7.1 Disaster Scenario: Accidental Deletion

```bash
# Oops! Someone accidentally deleted everything
kubectl delete ns default
# namespace "default" deleted

# Don't panic! Restore from backup
velero restore create --from-backup daily-backup-20250325-010000

# Watch restore progress
watch 'velero restore get'

# Expected output:
# NAME                                                STATUS       PROGRESS   STARTED
# daily-backup-20250325-010000-20250325-143530  InProgress   12/45      about 1 minute ago
```

### 7.2 Restore Entire Cluster

```bash
# Full cluster restore (all namespaces, all resources)
RESTORE_NAME="cluster-restore-$(date +%Y%m%d-%H%M%S)"

velero restore create $RESTORE_NAME \
  --from-backup daily-backup-20250325-010000

# Monitor restore progress
velero restore describe $RESTORE_NAME --details

# Watch real-time progress
watch 'velero restore get $RESTORE_NAME'

# View restore logs
velero restore logs $RESTORE_NAME
```

### 7.3 Restore Specific Namespace

```bash
# Restore only the default namespace
velero restore create restore-app-namespace \
  --from-backup daily-backup-20250325-010000 \
  --include-namespaces default

# Restore multiple namespaces
velero restore create restore-production \
  --from-backup daily-backup-20250325-010000 \
  --include-namespaces default,monitoring
```

### 7.4 Selective Restore (Exclude Resources)

```bash
# Restore everything except Secrets (security review first)
velero restore create restore-no-secrets \
  --from-backup daily-backup-20250325-010000 \
  --exclude-resources secrets

# Restore only Deployments and ConfigMaps
velero restore create restore-config \
  --from-backup daily-backup-20250325-010000 \
  --include-resources deployments,configmaps
```

### 7.5 Verify Restore Success

```bash
# Check restore status
velero restore get

# Get detailed restore info
velero restore describe cluster-restore-20250325-143530 --details

# Verify Kubernetes resources were restored
kubectl get all -n default

# Verify Argo CD is syncing
kubectl get deployment -n argocd
kubectl get applications

# Verify Spring Boot app is running
kubectl get pods -n default
kubectl logs -n default -l app=spring-boot-kubernetes --tail=20

# Verify Ingress is restored
kubectl get ingress

# Verify certificates were restored
kubectl get certificate

# Test application access
curl https://myapp.haryana.com/health
```

---

## Part 8: Cross-Region Disaster Recovery

### 8.1 Setup: Prepare for Regional Failure

**In your primary region (ap-south-1):**

```bash
# Create daily backups (already done above)
velero schedule create daily-backup --schedule="0 1 * * *" --ttl 720h0m0s

# Verify backups are going to S3
aws s3 ls s3://haryana-eks-backups/ --recursive
```

### 8.2 When Regional Outage Occurs

**Step 1: Create New EKS Cluster in Different Region**

```bash
# In a new region (e.g., us-east-1)
CLUSTER_NAME="spring-boot-eks-cluster-dr"
REGION="us-east-1"

# Create cluster (abbreviated, see EKS docs for full details)
aws eks create-cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --version 1.28 \
  --roleArn <eks-service-role-arn>

# Create node group
aws eks create-nodegroup \
  --cluster-name $CLUSTER_NAME \
  --nodegroup-name worker-nodes \
  --subnets <subnet-ids> \
  --node-role <node-role-arn> \
  --region $REGION
```

**Step 2: Install Velero in New Region**

```bash
# The S3 bucket is in ap-south-1, but we can still access it from us-east-1
# We need a bucket in the new region (us-east-1) or use the same bucket

# Option 1: Create regional backup in new region (recommended long-term)
aws s3api create-bucket \
  --bucket haryana-eks-backups-us-east-1 \
  --region us-east-1

# Option 2: Reuse primary bucket (if accessible cross-region)
# S3 buckets are already globally accessible, so we can reuse it!

# Install Velero with cross-region access
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.9.0 \
  --bucket haryana-eks-backups \
  --backup-location-config region=ap-south-1 \
  --snapshot-location-config region=ap-south-1 \
  --secret-file ./credentials-velero

# Note: S3 bucket is in ap-south-1, Velero runs in us-east-1 - both work!
```

**Step 3: List Available Backups**

```bash
# List all backups from primary region
velero backup get

# Expected output:
# NAME                          STATUS      CREATED                         EXPIRES
# daily-backup-20250325-010000  Completed   2025-03-25 01:00:31 +0000 UTC  2025-04-24 01:00:31 +0000 UTC
# daily-backup-20250324-010000  Completed   2025-03-24 01:00:31 +0000 UTC  2025-04-23 01:00:31 +0000 UTC
```

**Step 4: Restore in New Region**

```bash
# Restore from backup taken in ap-south-1, now restoring in us-east-1
velero restore create cluster-restore-dr \
  --from-backup daily-backup-20250325-010000

# Monitor restoration
watch 'velero restore get'

# Verify everything is restored
kubectl get all
kubectl get ingress
kubectl get certificate
```

### 8.3 Update DNS After Failover

```bash
# Get new Ingress Controller's Load Balancer DNS
kubectl get svc -n ingress-nginx

# Update DNS CNAME record to point to new load balancer
# myapp.haryana.com CNAME → <new-load-balancer-dns>

# Wait for DNS propagation (5-10 minutes)
nslookup myapp.haryana.com

# Verify application is accessible
curl https://myapp.haryana.com/health
```

---

## Part 9: Backup Policies and Retention

### 9.1 Define Backup Retention Policies

```bash
# Daily backups kept for 30 days
velero schedule create daily-backup \
  --schedule="0 1 * * *" \
  --ttl 720h0m0s

# Weekly backups kept for 90 days
velero schedule create weekly-backup \
  --schedule="0 2 * * 0" \
  --ttl 2160h0m0s

# Monthly backups kept for 1 year
velero schedule create monthly-backup \
  --schedule="0 3 1 * *" \
  --ttl 8760h0m0s
```

### 9.2 Monitor Backup Storage

```bash
# Check total backup size
aws s3 ls s3://haryana-eks-backups/ --recursive --summarize

# Expected output:
# Total Size: 2.3 GiB
# Total Objects: 150

# Get backup size breakdown
aws s3 ls s3://haryana-eks-backups/ --recursive --human-readable --summarize
```

### 9.3 Cleanup Old Backups (TTL Auto-Expiry)

```bash
# Velero automatically deletes expired backups based on TTL
# But you can manually delete if needed

# Delete a specific backup
velero backup delete daily-backup-20250310-010000

# Delete all backups older than a certain date
# (Velero's TTL handles this automatically)

# View backup expiration times
velero backup get -o wide
```

---

## Part 10: Monitoring and Maintenance

### 10.1 Monitor Velero Health

```bash
# Check Velero pod status
kubectl get pods -n velero

# View Velero logs
kubectl logs -n velero -l app.kubernetes.io/name=velero

# Check recent backup status
velero backup get --limit 10

# Get detailed backup info
velero backup describe daily-backup-20250325-010000
```

### 10.2 Test Restore Procedures

```bash
# Regularly test restore procedures (monthly recommended)
# This ensures backups actually work when you need them!

# Test 1: Restore to temporary namespace
velero restore create test-restore-$(date +%Y%m%d) \
  --from-backup daily-backup-20250325-010000 \
  --namespace-mappings default=test-restore

# Verify restore worked
kubectl get all -n test-restore

# Cleanup test restore
kubectl delete ns test-restore

# Test 2: Restore in same cluster (with name mapping)
velero restore create test-restore-same-cluster \
  --from-backup daily-backup-20250325-010000 \
  --namespace-mappings default=default-restored

# Verify
kubectl get all -n default-restored

# Cleanup
kubectl delete ns default-restored
```

### 10.3 Create CloudWatch Alarms for Backup Failures

```bash
# Alert if backup fails
aws cloudwatch put-metric-alarm \
  --alarm-name velero-backup-failed \
  --alarm-description "Alert if Velero backup fails" \
  --metric-name FailedBackups \
  --namespace Velero \
  --statistic Sum \
  --period 3600 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions arn:aws:sns:ap-south-1:123456789012:alerts-topic

# Alert if no backup in 25 hours
aws cloudwatch put-metric-alarm \
  --alarm-name velero-no-recent-backup \
  --alarm-description "Alert if no backup in 25 hours" \
  --metric-name BackupAge \
  --namespace Velero \
  --statistic Maximum \
  --period 3600 \
  --threshold 90000 \
  --comparison-operator GreaterThanThreshold
```

---

## Part 11: Troubleshooting Velero

### 11.1 Backup Fails

**Symptom:** Backup status shows "Failed"

```bash
# Check backup logs for error details
velero backup logs daily-backup-20250325-010000

# Common causes:
# 1. S3 bucket access denied
#    → Check IAM permissions
#    → Check credentials-velero file
# 2. EBS snapshot failed
#    → Check AWS account EBS limits
#    → Check volume encryption
# 3. Insufficient disk space
#    → Check velero pod storage
```

### 11.2 Restore Hangs

**Symptom:** Restore stuck at "InProgress"

```bash
# Check restore logs
velero restore logs cluster-restore-20250325

# Check for stuck resources
kubectl get pods -n velero
kubectl describe pod velero-* -n velero

# Common causes:
# 1. PVC binding takes too long
#    → Check PV and PVC status
# 2. Pod startup dependencies
#    → Check pod readiness probes
# 3. Resource quotas preventing creation
#    → Check ResourceQuota status
```

### 11.3 Velero Pod Not Running

**Symptom:** Pod in Pending or CrashLoopBackOff state

```bash
# Check pod status
kubectl describe pod velero-* -n velero

# Check logs
kubectl logs velero-* -n velero

# Common causes:
# 1. Missing credentials secret
#    → Reinstall with correct --secret-file
# 2. Node affinity issues
#    → Check node labels and taints
# 3. Resource limits
#    → Check CPU/memory requests
```

### 11.4 S3 Bucket Access Denied

**Symptom:** "AccessDenied" in backup logs

```bash
# Verify IAM user has S3 permissions
aws iam get-user-policy --user-name velero-backup-user --policy-name velero-backup-policy

# Test S3 access manually
aws s3 ls s3://haryana-eks-backups/

# Check bucket policy allows the IAM user
aws s3api get-bucket-policy --bucket haryana-eks-backups
```

---

## Part 12: Advanced: Backup Hooks & Filters

### 12.1 Backup with Pre/Post Hooks (Advanced)

```yaml
# Create a backup that runs a database dump before backup
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: database-aware-backup
spec:
  ttl: 720h0m0s
  hooks:
    resources:
    - name: database-dump
      includedNamespaces:
      - default
      includedResources:
      - pods
      labelSelector:
        matchLabels:
          app: postgres
      pre:
      - exec:
          container: postgres
          command: ["/bin/bash", "-c", "pg_dump > /backup/db.sql"]
          waitTimeout: 30m
```

### 12.2 Backup with Resource Filters

```bash
# Backup only resources with specific labels
velero backup create labeled-backup \
  --selector=backup=true

# Backup resources matching annotation
velero backup create app-backup \
  --selector=velero.io/exclude!=true
```

---

## 📁 Updated Repository Structure

Your project now includes Velero configuration:

```
spring-boot-kubernetes/
├── .github/
│   └── workflows/
│       └── ci.yml
├── k8s/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── issuer.yaml
│   ├── secret.yaml
│   ├── service-monitor.yaml
│   ├── hpa.yaml
│   ├── quota.yaml
│   ├── limitrange.yaml
│   └── velero-backup-schedule.yaml  # 🆕 Velero schedules
├── velero/
│   ├── backup-schedule.sh            # 🆕 Velero setup script
│   ├── restore-procedures.md         # 🆕 DR procedures
│   └── disaster-recovery-plan.md     # 🆕 RTO/RPO documentation
├── src/main/
│   ├── java/...
│   ├── resources/db/migration/
│   └── resources/application.properties
└── pom.xml
```

---

## Part 13: Disaster Recovery Plan Documentation

### 13.1 Create RTO/RPO Definition

**RTO (Recovery Time Objective):** Maximum acceptable downtime
**RPO (Recovery Point Objective):** Maximum acceptable data loss

```
Service: Spring Boot Application

RTO (Recovery Time Objective):
├── Scenario 1: Pod crash → 5 minutes (auto-restart)
├── Scenario 2: Node crash → 15 minutes (reschedule pods)
├── Scenario 3: Cluster failure → 2 hours (new cluster + restore)
└── Scenario 4: Region outage → 4 hours (new region + restore)

RPO (Recovery Point Objective):
├── Default: Hourly backups = 1 hour max data loss
├── If more critical: Implement 15-minute backups
└── Database: Separate RDS automated backups (5-minute increments)
```

### 13.2 Create Runbook Document

```markdown
# Disaster Recovery Runbook

## Incident: Accidental Namespace Deletion

### Diagnosis
- kubectl delete ns default executed by mistake
- All workloads in default namespace gone
- Argo CD unable to sync (no namespace)

### Recovery Procedure
1. [ ] Confirm data loss (check recent backups)
2. [ ] Create new EKS cluster (if entire cluster lost)
3. [ ] Install Velero in new cluster
4. [ ] Run: velero restore create --from-backup daily-backup-YYYYMMDD
5. [ ] Monitor restore progress
6. [ ] Verify applications are running
7. [ ] Test external connectivity (DNS, HTTPS)
8. [ ] Post-incident review

### RTO: 30 minutes
### RPO: 1 hour (last backup)
```

---

## Part 14: Backup Schedule YAML

You can commit Velero schedules to Git:

```yaml
# k8s/velero-backup-schedule.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: velero-schedules
  namespace: velero
data:
  daily-backup: |
    Schedule: 0 1 * * *
    TTL: 720h0m0s
    Description: Daily cluster backup at 1 AM UTC
  
  weekly-backup: |
    Schedule: 0 2 * * 0
    TTL: 2160h0m0s
    Description: Weekly backup on Sundays at 2 AM UTC
---
# Apply schedules after ConfigMap
# kubectl apply -f k8s/velero-backup-schedule.yaml
# velero schedule create daily-backup --schedule="0 1 * * *" --ttl 720h0m0s
# velero schedule create weekly-backup --schedule="0 2 * * 0" --ttl 2160h0m0s
```

---

## ✅ Disaster Recovery Verification Checklist

Before considering DR setup complete, verify:

- [ ] S3 bucket created for Velero backups
- [ ] IAM user created with S3 and EBS permissions
- [ ] Velero CLI installed locally
- [ ] Velero server installed in EKS cluster
- [ ] Backup storage location configured and available
- [ ] Volume snapshot location configured
- [ ] Daily backup schedule created
- [ ] First manual backup completed successfully
- [ ] Backup contents verified (resources present)
- [ ] Test restore to temporary namespace completed
- [ ] Cross-region backup strategy documented
- [ ] RTO/RPO metrics defined
- [ ] Disaster recovery runbook created
- [ ] Team trained on restoration procedures
- [ ] Monitoring and alerts configured for backup failures

---

## 📊 Backup Schedule Example

```
Backup Schedule:
├── Daily (every 1 AM UTC)
│   ├── Backup Name: daily-backup-{timestamp}
│   ├── Size: ~2-3 GB
│   ├── Retention: 30 days
│   └── Resources: Full cluster state
│
├── Weekly (every Sunday 2 AM UTC)
│   ├── Backup Name: weekly-backup-{timestamp}
│   ├── Size: ~2-3 GB
│   ├── Retention: 90 days
│   └── Resources: Full cluster state
│
└── Monthly (1st of month 3 AM UTC)
    ├── Backup Name: monthly-backup-{timestamp}
    ├── Size: ~2-3 GB
    ├── Retention: 1 year
    └── Resources: Full cluster state

Total Storage (monthly):
├── Daily: 30 backups × 2.5 GB = 75 GB
├── Weekly: 13 backups × 2.5 GB = 32.5 GB
├── Monthly: 12 backups × 2.5 GB = 30 GB
└── Total: ~137.5 GB/year (very cheap in S3)
```

---

## 🔗 Useful Resources

- [Velero Documentation](https://velero.io/docs/)
- [Velero AWS Plugin](https://github.com/vmware-tanzu/velero-plugin-for-aws)
- [AWS EBS Snapshots](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-snapshots.html)
- [S3 Lifecycle Policies](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html)
- [Disaster Recovery Best Practices](https://aws.amazon.com/blogs/architecture/disaster-recovery-dr-architecture-on-aws/)

---

## 🎉 Summary

Your enterprise-grade disaster recovery setup now provides:

1. ✅ **Full Cluster Backup:** Every resource in Git-like fashion
2. ✅ **Automated Schedules:** Daily, weekly, monthly backups without manual intervention
3. ✅ **Point-in-Time Recovery:** Restore from any previous backup
4. ✅ **Persistent Data Protection:** EBS snapshots for stateful data
5. ✅ **Cross-Region DR:** Failover to different AWS region if needed
6. ✅ **RTO/RPO Optimization:** Defined recovery targets and data loss thresholds
7. ✅ **Tested Procedures:** Regular restore tests ensure backups work
8. ✅ **Complete Auditability:** Every backup logged and traceable

**Your Spring Boot application on EKS now has enterprise-grade disaster recovery!** 🛡️🚀

---

## 🆘 The "Big Red Button" Ready Reference

```bash
# When disaster strikes, remember:

# 1. Don't panic - you have backups!
velero backup get  # See all available backups

# 2. Create new cluster (if needed)
# (see AWS EKS documentation)

# 3. Install Velero in new cluster
velero install --provider aws --bucket haryana-eks-backups ...

# 4. Press the big red button!
velero restore create --from-backup daily-backup-20250325-010000

# 5. Monitor progress
watch 'velero restore get'

# 6. Verify everything
kubectl get all
kubectl get ingress
kubectl get certificate

# Your cluster is back online! ✨
```
