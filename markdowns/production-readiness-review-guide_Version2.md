# ✅ Production Readiness Review (PRR): The Golden Gate to Live

## Overview

This is the final "Golden Gate" before you go live. In high-scale engineering, a **Production Readiness Review (PRR)** ensures that you haven't just built a "working" system, but a **"resilient"** one.

Below is your **comprehensive PRR checklist**. It integrates every component we've built:
- ☕ Spring Boot application in Java 21
- 🐳 Docker containerization
- 🚀 GitHub Actions CI/CD pipeline
- 🔄 Argo CD GitOps deployment
- ☸️ EKS Kubernetes cluster in AWS
- 🔒 NGINX Ingress + Let's Encrypt SSL
- 📊 Prometheus + Grafana monitoring
- 🛡️ Velero disaster recovery
- 🗄️ Flyway database migrations
- 🎛️ Resource quotas and scaling
- And more!

**This PRR is NOT optional.** Running production without it is like piloting an aircraft without a pre-flight checklist.

---

## How to Use This PRR

### Step 1: Print or Export This Checklist
```bash
# Save as PDF or print
# Assign a PRR Lead (usually the Platform/DevOps engineer)
# Schedule 2-3 hours for the review
```

### Step 2: Go Through Each Section
- Answer "YES" or "NO" for each checkbox
- If "NO", create a GitHub issue and fix it before going live
- Get sign-off from team lead

### Step 3: Post-Launch
- Keep this checklist for 6 months
- Use it for quarterly resilience reviews
- Update based on incidents

---

## 📋 The Complete PRR Checklist

---

## Section 1: 🏗️ Infrastructure & Scaling

### 1.1 Cluster Configuration

- [ ] **EKS Cluster Version**: Running Kubernetes 1.27+ (not EOL)
  ```bash
  kubectl version --short
  # Expected: v1.28.x or newer
  ```

- [ ] **Multi-AZ Setup**: Worker nodes spread across at least 2 Availability Zones
  ```bash
  kubectl get nodes --show-labels | grep topology.kubernetes.io/zone
  # Expected: ap-south-1a, ap-south-1b, ap-south-1c
  ```

- [ ] **Node Group Configuration**: At least 2 nodes, proper instance types
  ```bash
  kubectl get nodes
  # Expected: ≥2 nodes, instance type matches workload (t3.medium or better)
  ```

- [ ] **AWS Tags**: All resources tagged for cost allocation and automation
  ```bash
  # Check cluster tags
  aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.tags'
  # Expected: Environment=production, Team=haryana, CostCenter=xxxx
  ```

### 1.2 Scaling Configuration

- [ ] **Cluster Autoscaler**: Installed and verified
  ```bash
  kubectl get pods -n kube-system | grep cluster-autoscaler
  # Expected: Running pod with recent deployment
  ```

- [ ] **Cluster Autoscaler Logs**: No errors in past 24 hours
  ```bash
  kubectl logs -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler --tail=50
  # Expected: "Discovering k8s.io/cluster-autoscaler/enabled" messages
  ```

- [ ] **ASG Tags Correct**: Auto Scaling Group has required tags
  ```bash
  CLUSTER_NAME="your-cluster"
  aws autoscaling describe-auto-scaling-groups \
    --query "AutoScalingGroups[?Tags[?Key=='k8s.io/cluster-autoscaler/$CLUSTER_NAME']].Tags" \
    --output table
  # Expected: k8s.io/cluster-autoscaler/enabled=true, k8s.io/cluster-autoscaler/$CLUSTER_NAME=owned
  ```

- [ ] **HPA Configured**: Horizontal Pod Autoscaler deployed and active
  ```bash
  kubectl get hpa
  # Expected: At least 1 HPA with targets showing
  ```

- [ ] **HPA Resource Requests**: All Pods have CPU/memory requests
  ```bash
  kubectl describe deployment spring-boot-kubernetes | grep -A5 "Requests"
  # Expected: 250m CPU, 512Mi memory (or similar)
  ```

- [ ] **HPA Scaling Verified**: Test with load to confirm scaling works
  ```bash
  # Generate load
  kubectl run -it load-generator --image=busybox /bin/sh
  while true; do wget -q -O- http://spring-boot-kubernetes-service:8080; done
  
  # In another terminal, watch scaling
  watch 'kubectl get hpa'
  # Expected: REPLICAS column increases over time
  ```

- [ ] **Scale Down Verified**: Pods and nodes scale down after low demand
  ```bash
  # Stop load generator and wait 10+ minutes
  # Watch nodes: kubectl get nodes
  # Expected: Nodes decrease after 10-15 minutes
  ```

### 1.3 Resource Quotas & Limits

- [ ] **ResourceQuota**: Defined for namespace
  ```bash
  kubectl get resourcequota
  # Expected: At least 1 quota present
  kubectl describe resourcequota team-haryana-quota
  # Expected: Shows hard limits for CPU, memory, pods
  ```

- [ ] **LimitRange**: Enforces min/max resources per pod
  ```bash
  kubectl get limitrange
  # Expected: pod-limit-range present
  ```

- [ ] **All Pods Have Requests/Limits**: No "resource: {}" entries
  ```bash
  kubectl get pods -o json | jq '.items[] | select(.spec.containers[].resources | length == 0)' | wc -l
  # Expected: 0 (all pods have defined resources)
  ```

- [ ] **Quota Not Exceeded**: Current usage well below limits
  ```bash
  kubectl describe resourcequota team-haryana-quota
  # Expected: Used << Hard (e.g., Used: 500m/4000m CPU)
  ```

### 1.4 Network & Connectivity

- [ ] **Security Groups**: Properly configured for EKS
  ```bash
  # Check EKS node security group
  aws ec2 describe-security-groups \
    --filters "Name=tag:Name,Values=eks-node-sg" \
    --query 'SecurityGroups[0]'
  # Expected: Allows ingress from ALB, egress to internet
  ```

- [ ] **VPC Subnets**: Properly tagged for EKS
  ```bash
  aws ec2 describe-subnets --query 'Subnets[*].[SubnetId, Tags]' --output table
  # Expected: kubernetes.io/cluster/cluster-name=shared or owned
  ```

- [ ] **Network Policies (Optional)**: If using Calico/Cilium
  ```bash
  kubectl get networkpolicies --all-namespaces
  # Expected: Policies restrict traffic as needed
  ```

---

## Section 2: 🔐 Security & Compliance

### 2.1 Secrets Management

- [ ] **No Secrets in Git**: Database passwords, API keys NOT committed
  ```bash
  # Scan Git history for secrets
  git log --all --source --full-history --oneline -- \
    | grep -i "password\|secret\|key\|token" | wc -l
  # Expected: 0
  
  # Or use tools like git-secrets or truffleHog
  ```

- [ ] **Kubernetes Secrets Used**: Database credentials injected via secrets
  ```bash
  kubectl get secret db-credentials
  # Expected: Secret exists and contains: host, port, name, username, password
  
  # Verify they're NOT in deployment YAML
  grep -r "DB_PASSWORD=" k8s/deployment.yaml
  # Expected: No matches (use valueFrom.secretKeyRef instead)
  ```

- [ ] **Secrets Encrypted at Rest**: Kubernetes secrets encryption enabled
  ```bash
  # Check if KMS encryption is enabled for secrets
  aws eks describe-cluster --name $CLUSTER_NAME \
    --query 'cluster.logging.clusterLogging[?types[]=="audit"]'
  # Expected: Logging enabled (shows audit trails)
  ```

- [ ] **Slack Webhook Not in Git**: Slack webhook stored only as GitHub Secret
  ```bash
  grep -r "hooks.slack.com" .
  # Expected: No matches (stored in GitHub Secrets, not code)
  ```

### 2.2 SSL/TLS & HTTPS

- [ ] **Certificate Active & Valid**: HTTPS is working without warnings
  ```bash
  curl -I https://myapp.haryana.com
  # Expected: HTTP/2 200 OK
  # Expected: No certificate warnings
  ```

- [ ] **Certificate Expiration**: Not expiring within 30 days
  ```bash
  # Check certificate via Kubernetes
  kubectl get certificate myapp-tls-secret
  # Expected: READY=True, STATUS=Issued
  
  # Check expiration date
  echo | openssl s_client -servername myapp.haryana.com \
    -connect myapp.haryana.com:443 2>/dev/null \
    | openssl x509 -noout -dates
  # Expected: notAfter date is >30 days away
  ```

- [ ] **Certificate Renewal**: Cert-Manager active and monitoring
  ```bash
  kubectl get pods -n cert-manager
  # Expected: cert-manager pod running
  
  # Check if renewal is scheduled
  kubectl get certificate -o wide
  # Expected: READY=True
  ```

- [ ] **HTTP to HTTPS Redirect**: HTTP requests redirect to HTTPS
  ```bash
  curl -I http://myapp.haryana.com
  # Expected: HTTP/1.1 301 Moved Permanently
  # Expected: Location: https://myapp.haryana.com
  ```

### 2.3 IAM & RBAC

- [ ] **IAM Least Privilege**: Roles have minimum required permissions
  ```bash
  # Review Velero user permissions
  aws iam get-user-policy --user-name velero-backup-user --policy-name velero-backup-policy
  # Expected: Specific S3 bucket ARN, specific EC2 actions (not *)
  
  # Review EKS node role permissions
  ROLE_NAME=$(aws eks describe-nodegroup \
    --cluster-name $CLUSTER_NAME --nodegroup-name worker-nodes \
    --query 'nodegroup.nodeRole' --output text | cut -d/ -f2)
  aws iam list-role-policies --role-name $ROLE_NAME
  # Expected: Only needed policies (EC2, ECR, CloudWatch, etc.)
  ```

- [ ] **EKS Pod Identity**: Using IRSA (IAM Roles for Service Accounts)
  ```bash
  kubectl get serviceaccount velero -n velero -o yaml | grep annotations
  # Expected: eks.amazonaws.com/role-arn annotation present
  ```

- [ ] **GitHub Actions Permissions**: Write access only to necessary resources
  ```bash
  # Check GitHub Actions workflow permissions
  cat .github/workflows/ci.yml | grep -A5 "permissions:"
  # Expected: Only necessary permissions, not full read/write all
  ```

- [ ] **No Root Containers**: Security policy prevents running as root
  ```bash
  kubectl get pod -o jsonpath='{.items[*].spec.containers[*].securityContext.runAsUser}'
  # Expected: Non-zero UIDs (e.g., 1000, not 0)
  ```

### 2.4 Compliance & Auditing

- [ ] **Audit Logging Enabled**: Kubernetes audit logs captured
  ```bash
  aws eks describe-cluster --name $CLUSTER_NAME \
    --query 'cluster.logging.clusterLogging' --output table
  # Expected: audit=Enabled
  ```

- [ ] **CloudWatch Logs**: EKS logs forwarding to CloudWatch
  ```bash
  aws logs describe-log-groups --query 'logGroups[?contains(logGroupName, `/aws/eks/`)].logGroupName'
  # Expected: At least /aws/eks/cluster-name/cluster log group
  ```

- [ ] **Tag Compliance**: All resources properly tagged
  ```bash
  # Check Kubernetes resources have labels
  kubectl get all --all-namespaces -o json | jq '.items[] | select(.metadata.labels | length == 0)' | wc -l
  # Expected: 0 (all have labels)
  ```

---

## Section 3: 🚀 CI/CD & GitOps

### 3.1 GitHub Actions Pipeline

- [ ] **CI Pipeline Runs Successfully**: Latest commit passed all checks
  ```bash
  # Check GitHub Actions status
  # Go to: https://github.com/YuvrajSharma7/spring-boot-kubernetes/actions
  # Expected: Green checkmarks on recent commits
  ```

- [ ] **Tests Pass**: Unit and integration tests running
  ```bash
  # Local test to verify
  mvn clean test
  # Expected: BUILD SUCCESS
  ```

- [ ] **Docker Build Succeeds**: Image building and pushing to ECR
  ```bash
  # Check recent image in ECR
  aws ecr describe-images --repository-name spring-boot-kubernetes \
    --query 'imageDetails[0]' | head -20
  # Expected: Recent image with correct tag
  ```

- [ ] **Image Scanning**: ECR image scan enabled for vulnerabilities
  ```bash
  aws ecr describe-image-scan-findings --repository-name spring-boot-kubernetes \
    --image-id imageTag=latest
  # Expected: Scan completed, ideally no HIGH/CRITICAL findings
  ```

- [ ] **Secrets Used Correctly**: GitHub Secrets for sensitive data
  ```bash
  # Verify workflow uses secrets
  grep -r "\${{ secrets\." .github/workflows/
  # Expected: AWS credentials, Slack webhook, etc. use secrets
  ```

### 3.2 Argo CD Configuration

- [ ] **Argo CD Installed**: Running in cluster
  ```bash
  kubectl get pods -n argocd
  # Expected: argocd-server, argocd-application-controller running
  ```

- [ ] **GitOps Repo Connected**: Argo CD can pull from GitHub
  ```bash
  # Check repository connection
  kubectl get secret -n argocd | grep repo
  # Expected: repository credentials present
  ```

- [ ] **Application Deployed**: Spring Boot app shows as "Synced"
  ```bash
  argocd app get spring-boot-kubernetes
  # Expected: Sync Status=Synced, Health Status=Healthy
  ```

- [ ] **Auto-Sync Enabled**: Automatic synchronization active
  ```bash
  # Check Application resource
  kubectl get application spring-boot-kubernetes -n argocd -o yaml \
    | grep -A5 "syncPolicy"
  # Expected: automated.prune=true, automated.selfHeal=true
  ```

- [ ] **Rollback Verified**: Can revert commit and auto-rollback works
  ```bash
  # Test procedure:
  # 1. Revert a recent commit: git revert HEAD
  # 2. Push to main: git push
  # 3. Watch Argo CD sync: argocd app watch spring-boot-kubernetes
  # 4. Verify old version deployed
  # 5. Revert the revert: git revert HEAD
  # 6. Verify new version deployed
  ```

- [ ] **Notification Configured**: Argo CD failures alert the team
  ```bash
  # Check Argo CD notification settings
  kubectl get configmap argocd-notifications-cm -n argocd
  # Expected: Slack or email notification configured
  ```

### 3.3 GitOps Best Practices

- [ ] **Infrastructure as Code**: All k8s/ files in Git
  ```bash
  ls -la k8s/
  # Expected: deployment.yaml, service.yaml, ingress.yaml, 
  #           issuer.yaml, service-monitor.yaml, hpa.yaml, 
  #           quota.yaml, limitrange.yaml
  ```

- [ ] **Kustomization or Helm**: Multi-environment support ready
  ```bash
  # Check if kustomize overlays exist
  find . -name kustomization.yaml
  # Expected: base/ and overlays/ structure for dev/staging/prod
  ```

- [ ] **No Manual Changes**: All changes go through Git
  ```bash
  # Verify no manual edits via kubectl apply
  # Review git log for all recent changes
  git log --oneline | head -20
  # Expected: All commits from code changes, not manual kubectl edits
  ```

- [ ] **Audit Trail**: Git commit history is clear
  ```bash
  git log --oneline -20
  # Expected: Clear, descriptive commit messages
  # Expected: No commits with message "manual fix" or "temp change"
  ```

---

## Section 4: 📊 Observability & Monitoring

### 4.1 Prometheus & Metrics

- [ ] **Prometheus Running**: Server collecting metrics
  ```bash
  kubectl get pods -n monitoring | grep prometheus
  # Expected: prometheus-0 pod running
  ```

- [ ] **Scrape Targets Healthy**: All targets being scraped
  ```bash
  # Access Prometheus UI (port-forward)
  kubectl port-forward -n monitoring svc/kube-stack-prometheus-prometheus 9090:9090 &
  # Visit http://localhost:9090/targets
  # Expected: All targets showing "Up" (green)
  ```

- [ ] **Spring Boot Metrics Exposed**: /actuator/prometheus endpoint works
  ```bash
  kubectl port-forward svc/spring-boot-kubernetes-service 8080:8080 &
  curl http://localhost:8080/actuator/prometheus | head -20
  # Expected: Prometheus-formatted metrics (lines starting with #)
  ```

- [ ] **Custom Metrics**: Application-specific metrics available
  ```bash
  curl http://localhost:8080/actuator/prometheus | grep "application_"
  # Expected: Custom metrics from your app
  ```

### 4.2 Grafana Dashboards

- [ ] **Grafana Accessible**: Dashboard available via HTTP/HTTPS
  ```bash
  # Access Grafana
  kubectl get svc -n monitoring kube-stack-prometheus-grafana
  # Expected: External IP assigned (LoadBalancer)
  
  curl -u admin:$PASSWORD http://grafana-url:3000/api/health
  # Expected: 200 OK response
  ```

- [ ] **Prometheus Data Source**: Connected and querying
  ```bash
  # In Grafana UI, check Configuration > Data Sources
  # Expected: Prometheus data source marked as "Healthy"
  ```

- [ ] **Application Dashboard**: Spring Boot metrics visible
  ```bash
  # View custom dashboard
  # Expected: JVM heap memory, CPU, response times visible
  # Expected: No "No data" errors
  ```

- [ ] **Node Metrics**: Cluster node health visible
  ```bash
  # Expected: Dashboard shows CPU, memory per node
  # Expected: All nodes showing healthy (not red)
  ```

- [ ] **Alert Rules Configured**: Alerts defined and evaluating
  ```bash
  # Check Prometheus alerts
  kubectl port-forward -n monitoring svc/kube-stack-prometheus-prometheus 9090:9090 &
  # Visit http://localhost:9090/alerts
  # Expected: At least 1 alert rule present (not in pending state)
  ```

### 4.3 Slack Notifications

- [ ] **Slack Integration Active**: Messages arriving in #devops-alerts
  ```bash
  # Trigger a test build failure
  # Expected: Slack message arrives within 3 minutes
  
  # Or manually test:
  curl -X POST -H 'Content-type: application/json' \
    --data '{"text":"Test alert"}' \
    $SLACK_WEBHOOK_URL
  ```

- [ ] **Build Success/Failure Messages**: Receiving proper notifications
  ```bash
  # Check #devops-alerts channel in Slack
  # Expected: Messages for successful and failed deployments
  # Expected: Include commit hash, author, status
  ```

- [ ] **Alert Messages**: Critical alerts triggering Slack messages
  ```bash
  # In Prometheus, trigger an alert
  # Expected: AlertManager sends to Slack
  # Expected: Message includes severity, alert name, details
  ```

- [ ] **No False Positives**: Alerts firing appropriately
  ```bash
  # Review Slack message history
  # Expected: Alerts correlate with actual issues
  # Expected: No excessive spam or false positives
  ```

### 4.4 Logging & Troubleshooting

- [ ] **kubectl logs Works**: Can view application logs
  ```bash
  kubectl logs -l app=spring-boot-kubernetes --tail=50
  # Expected: Recent application logs visible
  ```

- [ ] **Log Rotation**: Logs not consuming all disk space
  ```bash
  kubectl get nodes -o json | jq '.items[].status.allocatable.ephemeralStorage'
  # Expected: >20% disk space available on nodes
  ```

- [ ] **CloudWatch Logs (Optional)**: Logs forwarded to CloudWatch
  ```bash
  # If using CloudWatch
  aws logs describe-log-streams --log-group-name /aws/eks/cluster-name/application
  # Expected: Recent log streams present
  ```

---

## Section 5: 💾 Data & Persistence

### 5.1 Database Migrations

- [ ] **Flyway Initialized**: Migration history table created
  ```bash
  # Connect to database
  psql -h $DB_HOST -U $DB_USERNAME -d $DB_NAME
  
  # Query migration history
  SELECT * FROM flyway_schema_history ORDER BY installed_rank;
  # Expected: At least V1 migration present
  ```

- [ ] **Migrations Running on Startup**: Flyway executes on pod startup
  ```bash
  kubectl logs -l app=spring-boot-kubernetes | grep -i flyway
  # Expected: Lines like:
  # "Successfully validated X migrations"
  # "Migrating schema to version X"
  ```

- [ ] **Migration Validation**: No checksum mismatches
  ```bash
  kubectl logs -l app=spring-boot-kubernetes | grep -i "checksum"
  # Expected: No error messages about checksum mismatch
  ```

- [ ] **Multiple Migrations Present**: V2, V3, V4 etc. exist
  ```bash
  ls -la src/main/resources/db/migration/ | wc -l
  # Expected: >1 migration files (more than just V1)
  ```

### 5.2 Database Security

- [ ] **RDS Encryption**: Database encrypted at rest
  ```bash
  aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE \
    --query 'DBInstances[0].StorageEncrypted'
  # Expected: true
  ```

- [ ] **RDS Automated Backups**: Snapshots enabled and recent
  ```bash
  aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE \
    --query 'DBInstances[0].BackupRetentionPeriod'
  # Expected: >=7 (at least 7 days)
  
  # Check recent snapshot
  aws rds describe-db-snapshots --db-instance-identifier $DB_INSTANCE
  # Expected: Recent snapshot within last 24 hours
  ```

- [ ] **RDS Multi-AZ**: High availability enabled
  ```bash
  aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE \
    --query 'DBInstances[0].MultiAZ'
  # Expected: true
  ```

- [ ] **Database Credentials Rotated**: Not using default password
  ```bash
  # Manual check: verify password was changed from initial
  # Expected: Password is strong and unique (no default)
  ```

### 5.3 Backup & Disaster Recovery

- [ ] **Velero Installed**: Server pods running
  ```bash
  kubectl get pods -n velero
  # Expected: velero and node-agent pods running
  ```

- [ ] **Backup Schedule Active**: Daily backups executing
  ```bash
  velero schedule get
  # Expected: daily-backup schedule present and enabled
  ```

- [ ] **Successful Backups**: At least one complete backup present
  ```bash
  velero backup get
  # Expected: At least 1 backup with STATUS=Completed
  # Expected: Most recent backup within 25 hours
  ```

- [ ] **Backup Verification**: S3 bucket contains backup data
  ```bash
  aws s3 ls s3://haryana-eks-backups/ --recursive | wc -l
  # Expected: >0 (backups present in S3)
  
  # Check size
  aws s3 ls s3://haryana-eks-backups/ --recursive --summarize | tail -1
  # Expected: >100MB (substantial backup)
  ```

- [ ] **Restore Test Completed**: Successfully restored from backup
  ```bash
  # Manual test (document in runbook):
  # 1. Create test backup
  # 2. Restore to temporary namespace
  # 3. Verify resources restored
  # 4. Cleanup
  # Expected: Restore completed without errors
  ```

### 5.4 Data Integrity

- [ ] **Database Constraints**: Primary keys, foreign keys, unique constraints
  ```bash
  # Review your DB schema
  \d users  # In psql
  # Expected: Constraints visible on columns
  ```

- [ ] **Data Validation**: Application validates input before inserting
  ```bash
  # Review your JPA entities
  # Expected: @NotNull, @NotBlank, @Email annotations present
  # Expected: Custom validators for business logic
  ```

- [ ] **Referential Integrity**: Foreign key constraints enforced
  ```bash
  # Test by attempting to violate constraint
  # Expected: Database rejects invalid foreign key
  ```

---

## Section 6: ✨ Application & User Experience

### 6.1 Application Functionality

- [ ] **Health Check Endpoint Works**: /actuator/health returns 200
  ```bash
  curl http://myapp.haryana.com/health
  # Expected: HTTP 200 with health status
  ```

- [ ] **Database Connectivity**: App can connect to database
  ```bash
  curl http://myapp.haryana.com/health | jq '.components.db'
  # Expected: "db": {"status": "UP"}
  ```

- [ ] **Core Functionality Works**: Main user flows tested
  ```bash
  # Manually test critical paths
  # Expected: Login, create data, retrieve data all work
  ```

- [ ] **Error Handling**: Bad requests return proper error codes
  ```bash
  curl -X POST http://myapp.haryana.com/api/invalid-data
  # Expected: 400 Bad Request (not 500 Internal Server Error)
  ```

### 6.2 Performance

- [ ] **Response Time**: P95 response time < 1 second
  ```bash
  # Check Grafana dashboard
  # Expected: histogram_quantile(0.95, rate(http_server_requests_seconds_bucket[5m])) < 1s
  ```

- [ ] **Throughput**: Can handle expected QPS (queries per second)
  ```bash
  # Check Prometheus metrics
  rate(http_server_requests_seconds_count[5m]) > expected_qps
  # Expected: Actual throughput >= expected peak load
  ```

- [ ] **Memory Stable**: No memory leak (heap not growing unbounded)
  ```bash
  # Check Grafana: JVM heap memory over 24 hours
  # Expected: Sawtooth pattern (increase during requests, decrease during GC)
  # Expected: NOT linearly increasing
  ```

- [ ] **CPU Reasonable**: CPU usage appropriate for load
  ```bash
  # Check Grafana: CPU usage vs request rate
  # Expected: CPU proportional to load
  # Expected: Not consistently >80% at normal load
  ```

### 6.3 User Experience

- [ ] **Page Load Time**: Website loads in <3 seconds
  ```bash
  # Test with browser developer tools
  curl -w "@curl-format.txt" -o /dev/null -s https://myapp.haryana.com
  # Expected: Total time < 3 seconds
  ```

- [ ] **Availability**: Uptime >99.9% over past 7 days
  ```bash
  # Check monitoring dashboard
  # Expected: No downtime incidents in past week
  # Expected: <43 seconds/week downtime target
  ```

- [ ] **Mobile Friendly**: App works on mobile browsers
  ```bash
  # Test on various devices or browser emulation
  # Expected: Responsive layout, readable fonts, working buttons
  ```

---

## Section 7: 🔄 Disaster Recovery & Resilience

### 7.1 Backup & Recovery

- [ ] **Velero Schedule Verified**: Backups run automatically
  ```bash
  velero schedule describe daily-backup
  # Expected: Next run time shows upcoming backup
  # Expected: Previous backups marked as completed
  ```

- [ ] **RTO Documented**: Recovery Time Objective defined
  ```bash
  # In your documentation
  # Expected: "RTO: 30 minutes for accidental deletion"
  # Expected: "RTO: 4 hours for regional outage"
  ```

- [ ] **RPO Documented**: Recovery Point Objective defined
  ```bash
  # In your documentation
  # Expected: "RPO: 1 hour (daily backups)"
  # Expected: "RPO: 5 minutes (RDS automated backups)"
  ```

- [ ] **Restore Runbook Created**: Written procedure for recovery
  ```bash
  # Document should exist
  cat velero/disaster-recovery-runbook.md
  # Expected: Step-by-step procedures for:
  #   - Pod failure recovery
  #   - Node failure recovery
  #   - Cluster failure recovery
  #   - Regional outage recovery
  ```

### 7.2 High Availability

- [ ] **Pod Replicas >= 2**: No single point of failure
  ```bash
  kubectl get deployment spring-boot-kubernetes
  # Expected: DESIRED >= 2, CURRENT >= 2
  ```

- [ ] **Pod Disruption Budget**: Protects against involuntary disruptions
  ```bash
  kubectl get poddisruptionbudget
  # Expected: At least 1 PDB for critical apps
  ```

- [ ] **Liveness Probes**: Pods restarted on failure
  ```bash
  kubectl describe deployment spring-boot-kubernetes | grep -A5 "Liveness"
  # Expected: livenessProbe configured
  ```

- [ ] **Readiness Probes**: Traffic not sent to unhealthy pods
  ```bash
  kubectl describe deployment spring-boot-kubernetes | grep -A5 "Readiness"
  # Expected: readinessProbe configured
  ```

### 7.3 Failover & Redundancy

- [ ] **Database Failover**: RDS Multi-AZ handles automatic failover
  ```bash
  # No manual action needed - verified in Section 5.2
  ```

- [ ] **Ingress Redundancy**: Multiple Ingress Controller instances
  ```bash
  kubectl get pods -n ingress-nginx
  # Expected: >=2 ingress-nginx controller pods
  ```

- [ ] **Node Failure Handled**: Pod can reschedule to another node
  ```bash
  # Test: cordon a node and watch pods reschedule
  kubectl cordon <node-name>
  # Expected: Pods evicted and rescheduled to another node
  kubectl uncordon <node-name>
  ```

---

## Section 8: 🛠️ Operations & Maintenance

### 8.1 Runbooks & Documentation

- [ ] **Deployment Runbook**: Procedure for deploying changes
  ```bash
  cat docs/deployment-runbook.md
  # Expected: Clear steps for pushing to main and monitoring Argo CD
  ```

- [ ] **Incident Response Runbook**: Procedure for common incidents
  ```bash
  cat docs/incident-response-runbook.md
  # Expected: Steps for: high CPU, high memory, pod crashes, DB errors
  ```

- [ ] **Troubleshooting Guide**: How to debug common issues
  ```bash
  cat docs/troubleshooting-guide.md
  # Expected: Covers: kubectl logs, port-forward, describe, events
  ```

- [ ] **Architectural Documentation**: System design documented
  ```bash
  cat docs/architecture.md
  # Expected: Explains: Spring Boot → Docker → EKS → Ingress → RDS flow
  ```

### 8.2 Team Preparedness

- [ ] **On-Call Setup**: Team members prepared for incidents
  ```bash
  # Expected: At least one person on-call 24/7 (for production)
  # Expected: Clear escalation procedure
  ```

- [ ] **Access Provisioning**: Team has necessary AWS/Kubernetes access
  ```bash
  # Expected: IAM users have least-privilege roles
  # Expected: kubectl access configured via kubeconfig
  ```

- [ ] **Notification Routing**: Team members alerted for critical issues
  ```bash
  # Expected: Slack alerts reach on-call person
  # Expected: Page alerts (Pagerduty/Opsgenie) for critical incidents
  ```

- [ ] **Regular Drills**: Incident response practiced
  ```bash
  # Expected: Team has conducted disaster recovery drills
  # Expected: Average recovery time documented
  # Expected: Improvements identified and tracked
  ```

### 8.3 Compliance & Governance

- [ ] **Change Management**: Procedure for production changes
  ```bash
  # Expected: Only changes via Git/GitHub
  # Expected: Peer review before merge to main
  # Expected: Argo CD auto-deploy after merge
  ```

- [ ] **Access Control**: Limited access to production
  ```bash
  # Expected: Only authorized team members can push to main
  # Expected: Branch protections enforced on main
  # Expected: Audit logging of all changes
  ```

- [ ] **Data Privacy**: GDPR/data protection compliance
  ```bash
  # Expected: Database encryption at rest
  # Expected: Encryption in transit (HTTPS)
  # Expected: No PII in logs
  # Expected: Data retention policy documented
  ```

### 8.4 Cost Optimization (Optional)

- [ ] **Resource Right-Sizing**: No overprovisioned resources
  ```bash
  # Check Kubernetes resource requests
  # Expected: Requests match actual usage (not overly generous)
  # Expected: Can point to Grafana charts justifying sizes
  ```

- [ ] **Spot Instances (Optional)**: Using spot for non-critical workloads
  ```bash
  # Expected: Node group uses spot instances (30-70% savings)
  # Expected: Disruption budget protects critical workloads
  ```

- [ ] **Reserved Instances**: Long-term commitments for predictable baseline
  ```bash
  # Expected: RI coverage for baseline load
  # Expected: >20% savings vs on-demand pricing
  ```

---

## Section 9: ☑️ Pre-Launch Sign-Off

### 9.1 Team Reviews

- [ ] **DevOps Team Approval**: Infrastructure and deployment verified
  ```
  Reviewed by: ________________
  Date: ________________
  Approved: [ ] Yes [ ] No
  ```

- [ ] **Application Team Approval**: Code and functionality verified
  ```
  Reviewed by: ________________
  Date: ________________
  Approved: [ ] Yes [ ] No
  ```

- [ ] **Security Team Approval**: Security and compliance reviewed
  ```
  Reviewed by: ________________
  Date: ________________
  Approved: [ ] Yes [ ] No
  ```

- [ ] **Product/Business Approval**: Product requirements met
  ```
  Reviewed by: ________________
  Date: ________________
  Approved: [ ] Yes [ ] No
  ```

### 9.2 Outstanding Issues

```
List any "NO" items that will be fixed post-launch:

Issue #1: ________________________
Risk Level: [ ] Low [ ] Medium [ ] High
Fix Timeline: ________________

Issue #2: ________________________
Risk Level: [ ] Low [ ] Medium [ ] High
Fix Timeline: ________________

Issue #3: ________________________
Risk Level: [ ] Low [ ] Medium [ ] High
Fix Timeline: ________________

Note: Only "Low" risk items acceptable for post-launch fixes!
```

### 9.3 Launch Go/No-Go Decision

```
FINAL DECISION:

[ ] GO TO PRODUCTION
    Signed by: ________________
    Date: ________________
    Time: ________________

[ ] NO-GO (Fix and re-review)
    Reason: ________________________________________
    Next review date: ________________
```

---

## 📊 PRR Summary Dashboard

Use this summary to track your compliance:

```
┌─────────────────────────────────────────────┐
│      PRODUCTION READINESS REVIEW SCORE      │
├─────────────────────────────────────────────┤
│ Section 1: Infrastructure & Scaling         │
│ ████████████████░░░░░░░░░░░░░░░░░░░░░░░░░  │  87%
│                                             │
│ Section 2: Security & Compliance            │
│ ██████████████████████░░░░░░░░░░░░░░░░░░░  │  95%
│                                             │
│ Section 3: CI/CD & GitOps                   │
│ ████████████████████░░░░░░░░░░░░░░░░░░░░  │  92%
│                                             │
│ Section 4: Observability & Monitoring       │
│ ████████████████████████░░░░░░░░░░░░░░░░  │  96%
│                                             │
│ Section 5: Data & Persistence               │
│ ████████████████████████░░░░░░░░░░░░░░░░  │  96%
│                                             │
│ Section 6: Application & UX                 │
│ ████████████████░░░░░░░░░░░░░░░░░░░░░░░░  │  83%
│                                             │
│ Section 7: DR & Resilience                  │
│ ████████████████████░░░░░░░░░░░░░░░░░░░░  │  91%
│                                             │
│ Section 8: Operations & Maintenance         │
│ █████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░  │  80%
│                                             │
├─────────────────────────────────────────────┤
│ OVERALL SCORE:                       91%    │
│ RECOMMENDATION:                   GO LIVE   │
└─────────────────────────────────────────────┘
```

---

## 🚀 Launch Day Checklist

On the day of launch:

```
72 Hours Before:
[ ] Final code review completed
[ ] All PRR items status confirmed
[ ] On-call rotation established
[ ] Notification channels tested

24 Hours Before:
[ ] Full system health check
[ ] Database backups verified
[ ] Team briefing completed
[ ] Rollback procedures reviewed

2 Hours Before:
[ ] Team assembled and ready
[ ] Communication channels open
[ ] Monitoring dashboards visible
[ ] Load testing completed

Launch Time:
[ ] Marketing team notified
[ ] Support team alerted
[ ] On-call person confirmed
[ ] Begin traffic migration

15 Minutes After:
[ ] Basic smoke tests passing
[ ] Error rate normal
[ ] Latency normal
[ ] User feedback positive

1 Hour After:
[ ] All metrics green
[ ] No critical alerts
[ ] Zero escalations
[ ] Team celebrates! 🎉

24 Hours After:
[ ] Production stability confirmed
[ ] All systems nominal
[ ] Team post-launch review
[ ] Document any learnings
```

---

## 📈 Post-Launch Monitoring (First 7 Days)

```
Daily Checks:
├── Error rate < 0.1%
├── P95 latency < 1 second
├── CPU average < 50%
├── Memory trend stable
├── Zero unexpected restarts
└── Team reports no issues

Weekly Review:
├── Total uptime: 99.9%+
├── Zero incidents
├── All backups successful
├── Scaling tested and working
└── Team satisfied with stability
```

---

## 🎓 Lessons Learned & Continuous Improvement

After 1 month in production, conduct:

```
Retrospective Review:
1. What went well?
2. What could be improved?
3. Were there any incidents? Root cause?
4. Did runbooks work?
5. Did alerts fire appropriately?
6. Recommendations for next deployment?

Document findings and update:
├── Runbooks (if procedures were wrong)
├── Alert thresholds (if too sensitive/insensitive)
├── Scaling parameters (if HPA triggered incorrectly)
├── Resource limits (if too tight/generous)
└── Documentation (if confusing)

Update PRR checklist for next time
```

---

## 🆘 If You Fail the PRR

It's **not a failure**—it's an investment in reliability!

```
For each "NO" item:

1. Create a GitHub Issue with details
2. Assign to responsible team member
3. Set target completion date (before production)
4. Link to this PRR checklist
5. Track progress
6. Re-test after fix
7. Update PRR checklist
8. Schedule follow-up review

Example Issue:
Title: "PRR: HPA scaling not tested end-to-end"
Body: "Load test showed HPA triggered, but nodes didn't scale.
      Issue: ASG tags missing k8s.io/cluster-autoscaler/enabled
      Fix: Add tags to ASG (AWS console or CLI)
      Test: Re-run load test and verify 5-min scale-out
      Timeline: Complete by 2025-03-30"
```

---

## 📋 PRR Version & History

```
PRR Checklist Version: 1.0
Last Updated: 2025-03-25
Next Review: 2025-06-25 (quarterly)

Completed PRR History:
├── v1.0 (2025-03-25) - Initial launch PRR - GO LIVE APPROVED
├── v1.1 (2025-06-25) - Quarterly review after 3 months - 5 items improved
├── v2.0 (2025-09-25) - Quarterly review after 6 months - Major improvements
└── [Future reviews...]
```

---

## 🎯 Final Thoughts

A **Production Readiness Review** is not bureaucracy—it's **insurance**.

You wouldn't fly on an aircraft without a pre-flight checklist.
You wouldn't operate on a patient without pre-op verification.
You shouldn't deploy to production without a PRR.

**Your system is production-ready when:**
- ✅ All boxes are checked (or risk explicitly accepted)
- ✅ Team is trained and confident
- ✅ Monitoring is comprehensive
- ✅ Runbooks are written and tested
- ✅ Backups are verified
- ✅ Alerts are configured
- ✅ Incident response plan is ready
- ✅ Everyone agrees it's safe

**Only then can you launch with confidence.** 🚀

---

## 📞 Questions During PRR?

```
If unsure about an item:

1. Check the relevant guide (Infrastructure, Security, etc.)
2. Ask the team member responsible for that area
3. Research in AWS documentation
4. Create a test environment to verify
5. Document your findings for future reference

Never assume something is done—verify it!
```

---

## ✅ PRR Completion Certificate

When all items are completed and signed off:

```
╔════════════════════════════════════════════╗
║   PRODUCTION READINESS REVIEW COMPLETE     ║
║                                            ║
║ Application: Spring Boot on EKS           ║
║ Region: ap-south-1                        ║
║ Date: 2025-03-25                          ║
║ Overall Score: 91%                        ║
║                                            ║
║ APPROVED FOR PRODUCTION LAUNCH ✅          ║
║                                            ║
║ DevOps:    ________________                ║
║ Security:  ________________                ║
║ Product:   ________________                ║
║ Business:  ________________                ║
║                                            ║
║ Safe travels! 🚀                           ║
╚════════════════════════════════════════════╝
```
