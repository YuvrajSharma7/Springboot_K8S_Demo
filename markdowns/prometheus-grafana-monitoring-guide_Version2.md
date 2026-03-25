# 📊 Enterprise Monitoring with Prometheus & Grafana

## Overview

To round out your enterprise-grade setup, we will install the **Prometheus + Grafana stack**. This provides "Observability"—the ability to see exactly how much Memory (RAM) and CPU your Spring Boot application is consuming in real-time.

With this stack, you'll be able to:
- 📈 Monitor CPU and memory usage in real-time
- 🔍 Track application metrics and performance
- 🚨 Set up alerts for threshold violations
- 📊 Create custom dashboards for your team
- 💾 Store historical metrics for trend analysis

---

## Architecture Overview

```
Spring Boot App (with Micrometer)
    ↓ (exposes /metrics/prometheus)
Prometheus (Scrapes metrics every 15s)
    ↓ (stores time-series data)
Grafana (Visualizes the data)
    ↓
Your Team (views beautiful dashboards)
```

---

## Prerequisites

Before starting, ensure you have:

- An EKS cluster running
- `kubectl` configured to access your cluster
- AWS Cloud Shell or local terminal with Helm installed
- Your Spring Boot application deployed on EKS

---

## Step 1: Install the Monitoring Stack with Helm

The easiest way to install Prometheus and Grafana on EKS is using **Helm**, the package manager for Kubernetes.

### 1.1 Add the Prometheus Community Helm Repository

```bash
# Add the Prometheus community repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

# Update your Helm repositories
helm repo update
```

### 1.2 Install the Kube-Stack-Prometheus Helm Chart

This chart bundles Prometheus, Grafana, AlertManager, and Node Exporter:

```bash
# Install the stack into a new 'monitoring' namespace
helm install kube-stack-prometheus prometheus-community/kube-stack-prometheus \
  --namespace monitoring \
  --create-namespace
```

**What this installs:**

| Component | Purpose |
|-----------|---------|
| **Prometheus** | Time-series database that scrapes metrics from your applications |
| **Grafana** | Visualization dashboard for metrics |
| **AlertManager** | Handles alerts and notifications |
| **Node Exporter** | Collects hardware and OS metrics from cluster nodes |
| **Kube-State-Metrics** | Converts Kubernetes objects into metrics |

### 1.3 Verify the Installation

Check that all monitoring pods are running:

```bash
# List all pods in the monitoring namespace
kubectl get pods -n monitoring

# Expected output (all pods should be Running):
# NAME                                           READY   STATUS    RESTARTS   AGE
# alertmanager-kube-stack-prometheus-0           1/1     Running   0          2m
# kube-stack-prometheus-grafana-xxxxx            1/1     Running   0          2m
# kube-stack-prometheus-kube-state-metrics-xxx   1/1     Running   0          2m
# kube-stack-prometheus-operator-xxxxx           1/1     Running   0          2m
# kube-stack-prometheus-prometheus-0              1/1     Running   0          2m
# node-exporter-xxxxx                            1/1     Running   0          2m
# node-exporter-xxxxx                            1/1     Running   0          2m
```

Wait for all pods to show `Running` status before proceeding.

---

## Step 2: Access the Grafana Dashboard

Grafana is the visual "frontend" where you see the graphs and dashboards. By default, it's a ClusterIP service (internal only). Let's expose it so you can access it from your browser.

### 2.1 Expose Grafana as a LoadBalancer

```bash
# Patch the Grafana service to change it from ClusterIP to LoadBalancer
kubectl patch svc kube-stack-prometheus-grafana \
  -n monitoring \
  -p '{"spec": {"type": "LoadBalancer"}}'
```

### 2.2 Get the Grafana External URL

```bash
# Get the AWS LoadBalancer DNS name
kubectl get svc -n monitoring kube-stack-prometheus-grafana
```

Expected output:
```
NAME                              TYPE           CLUSTER-IP      EXTERNAL-IP                                      PORT(S)
kube-stack-prometheus-grafana     LoadBalancer   10.100.50.200   aaaa1234-bbbb5678.us-east-1.elb.amazonaws.com   80:30123/TCP
```

Copy the **EXTERNAL-IP** (the AWS LoadBalancer DNS name). This is your Grafana URL:

```
http://aaaa1234-bbbb5678.us-east-1.elb.amazonaws.com
```

### 2.3 Get the Grafana Admin Password

Grafana comes with a pre-configured admin user. Get the password:

```bash
# Decode and print the admin password
kubectl get secret -n monitoring kube-stack-prometheus-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d

# Output example: prom-operator
```

### 2.4 Log In to Grafana

1. Open your browser and navigate to the Grafana URL (from step 2.2)
2. Log in with:
   - **Username:** `admin`
   - **Password:** (from step 2.3)
3. Change the default password when prompted

---

## Step 3: Connect Spring Boot to Prometheus

For your Spring Boot application to expose metrics that Prometheus can scrape, you need to add the Micrometer Prometheus dependency and enable the metrics endpoint.

### 3.1 Add Micrometer Prometheus Dependency

Update your `pom.xml`:

```xml
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

**Location in pom.xml:**
```xml
<project>
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>spring-boot-kubernetes</artifactId>
    
    <dependencies>
        <!-- Existing dependencies -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
        
        <!-- Add Micrometer Prometheus -->
        <dependency>
            <groupId>io.micrometer</groupId>
            <artifactId>micrometer-registry-prometheus</artifactId>
        </dependency>
        
        <!-- Other dependencies -->
    </dependencies>
</project>
```

### 3.2 Enable the Metrics Endpoint

Update your `application.properties` (or `application.yml`):

**application.properties:**
```properties
# Management endpoints
management.endpoints.web.exposure.include=health,info,prometheus
management.endpoint.health.show-details=always

# Metrics configuration
management.metrics.export.prometheus.enabled=true
management.metrics.distribution.percentiles-histogram.http.server.requests=true
```

**application.yml (alternative):**
```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
  endpoint:
    health:
      show-details: always
  metrics:
    export:
      prometheus:
        enabled: true
    distribution:
      percentiles-histogram:
        http.server.requests: true
```

### 3.3 Verify the Metrics Endpoint

After redeploying your Spring Boot application, verify that the metrics endpoint is accessible:

```bash
# Forward the port to your local machine
kubectl port-forward svc/spring-boot-kubernetes-service 8080:8080 -n default

# In another terminal, access the metrics endpoint
curl http://localhost:8080/actuator/prometheus

# You should see Prometheus-formatted metrics like:
# # HELP jvm_memory_used_bytes The amount of used memory
# # TYPE jvm_memory_used_bytes gauge
# jvm_memory_used_bytes{area="heap",id="PS Survivor Space"} 1.048576E7
```

---

## Step 4: Configure Prometheus to Scrape Spring Boot Metrics

By default, Prometheus needs to know where to find your Spring Boot metrics. We'll create a `ServiceMonitor` resource to tell Prometheus to scrape your app.

### 4.1 Create a ServiceMonitor (k8s/service-monitor.yaml)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: spring-boot-monitor
  namespace: default
  labels:
    release: kube-stack-prometheus
spec:
  selector:
    matchLabels:
      app: spring-boot-kubernetes
  endpoints:
  - port: metrics
    path: /actuator/prometheus
    interval: 30s
```

### 4.2 Update Your Service to Include Metrics Port

Update your `k8s/service.yaml` to expose a metrics port:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: spring-boot-kubernetes-service
spec:
  type: NodePort
  selector:
    app: spring-boot-kubernetes
  ports:
    - name: http
      protocol: TCP
      port: 8080
      targetPort: 8080
    - name: metrics
      protocol: TCP
      port: 9090
      targetPort: 8080  # Both point to 8080 (Spring Boot handles routing)
```

### 4.3 Deploy the ServiceMonitor

```bash
# Apply the ServiceMonitor
kubectl apply -f k8s/service-monitor.yaml

# Verify it was created
kubectl get servicemonitor -n default
```

---

## Step 5: Create Custom Grafana Dashboards

### 5.1 Use Pre-Built Dashboards

Grafana comes with several pre-built dashboards. To find them:

1. Log in to Grafana
2. Click the **+** icon (Create) in the left sidebar
3. Select **Import**
4. Search for popular dashboards:
   - **1860** - Node Exporter for Prometheus (system metrics)
   - **3662** - Prometheus (Prometheus server metrics)
   - **3119** - Kubernetes Cluster Monitoring (cluster-wide metrics)

### 5.2 Create a Custom Spring Boot Dashboard

For Spring Boot-specific metrics, create a new dashboard:

1. Go to **Create** → **Dashboard**
2. Click **Add new panel**
3. In the query editor, use Prometheus queries like:

```
# JVM Memory Usage
jvm_memory_used_bytes{instance=~"$Instance"}

# CPU Usage
rate(process_cpu_time_seconds_total[5m])

# HTTP Requests Per Second
rate(http_server_requests_seconds_count[1m])

# Response Time (95th percentile)
histogram_quantile(0.95, rate(http_server_requests_seconds_bucket[5m]))
```

4. Customize the visualization (choose graph type, colors, legend)
5. Click **Save** to save your dashboard

### 5.3 Example: Spring Boot Application Dashboard

Create a dashboard with these common panels:

| Panel Name | Query | Type |
|-----------|-------|------|
| JVM Heap Memory | `jvm_memory_used_bytes{area="heap"}` | Graph |
| CPU Usage | `rate(process_cpu_time_seconds_total[5m]) * 100` | Gauge |
| HTTP Requests/sec | `rate(http_server_requests_seconds_count[1m])` | Graph |
| Error Rate | `rate(http_server_requests_seconds_count{status=~"5.."}[1m])` | Graph |
| Response Time P95 | `histogram_quantile(0.95, rate(http_server_requests_seconds_bucket[5m]))` | Graph |

---

## Step 6: Set Up Alerts

### 6.1 Create an Alert Rule

Create `k8s/prometheus-alert.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: spring-boot-alerts
  namespace: monitoring
spec:
  groups:
  - name: spring-boot
    interval: 30s
    rules:
    - alert: HighMemoryUsage
      expr: |
        (jvm_memory_used_bytes{area="heap"} / jvm_memory_max_bytes{area="heap"}) > 0.9
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High JVM Heap Memory Usage"
        description: "JVM heap memory usage is above 90%"

    - alert: HighCPUUsage
      expr: |
        rate(process_cpu_time_seconds_total[5m]) > 0.8
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "High CPU Usage Detected"
        description: "CPU usage is above 80%"

    - alert: HighErrorRate
      expr: |
        rate(http_server_requests_seconds_count{status=~"5.."}[5m]) > 0.1
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: "High Error Rate Detected"
        description: "Error rate is above 10%"
```

Deploy the alert rules:

```bash
kubectl apply -f k8s/prometheus-alert.yaml
```

### 6.2 Connect AlertManager to Slack (Optional)

Create `k8s/alertmanager-config.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-kube-stack-prometheus
  namespace: monitoring
type: Opaque
stringData:
  alertmanager.yaml: |
    global:
      slack_api_url: 'YOUR_SLACK_WEBHOOK_URL'
    
    route:
      receiver: 'slack'
      group_by: ['alertname', 'cluster']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 12h
    
    receivers:
    - name: 'slack'
      slack_configs:
      - channel: '#devops-alerts'
        title: 'Prometheus Alert'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

Apply the configuration:

```bash
kubectl apply -f k8s/alertmanager-config.yaml
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
└── prometheus-alert.yaml        # Alert rules (optional)
```

---

## 🔍 Useful Kubernetes Monitoring Commands

```bash
# View monitoring namespace resources
kubectl get all -n monitoring

# Check Prometheus targets
kubectl port-forward -n monitoring svc/kube-stack-prometheus-prometheus 9090:9090
# Then visit: http://localhost:9090/targets

# Check AlertManager
kubectl port-forward -n monitoring svc/kube-stack-prometheus-alertmanager 9093:9093
# Then visit: http://localhost:9093

# View Prometheus logs
kubectl logs -n monitoring deploy/kube-stack-prometheus-prometheus

# View Grafana logs
kubectl logs -n monitoring deploy/kube-stack-prometheus-grafana
```

---

## 📊 Common Prometheus Queries for Spring Boot

Use these queries in Grafana to monitor your application:

### Memory Metrics
```promql
# Heap memory usage percentage
(jvm_memory_used_bytes{area="heap"} / jvm_memory_max_bytes{area="heap"}) * 100

# Non-heap memory usage
jvm_memory_used_bytes{area="non-heap"}
```

### CPU Metrics
```promql
# CPU usage percentage
rate(process_cpu_time_seconds_total[5m]) * 100

# System load average
node_load1
```

### HTTP Metrics
```promql
# Request rate (requests per second)
rate(http_server_requests_seconds_count[1m])

# Request duration (95th percentile)
histogram_quantile(0.95, rate(http_server_requests_seconds_bucket[5m]))

# Error rate
rate(http_server_requests_seconds_count{status=~"5.."}[1m])
```

### Custom Application Metrics
```promql
# If you created custom metrics in your app
application_custom_metric_name
```

---

## 🚨 Troubleshooting Monitoring

### Issue: Prometheus Not Scraping Spring Boot Metrics

**Solution:**
1. Verify the ServiceMonitor exists:
   ```bash
   kubectl get servicemonitor -n default
   ```

2. Check the Prometheus targets:
   ```bash
   kubectl port-forward -n monitoring svc/kube-stack-prometheus-prometheus 9090:9090
   # Visit http://localhost:9090/targets and look for your service
   ```

3. Verify metrics endpoint is accessible:
   ```bash
   kubectl exec -it <spring-boot-pod> -- curl http://localhost:8080/actuator/prometheus
   ```

### Issue: Grafana Dashboard Shows "No Data"

**Solution:**
1. Verify the Prometheus data source is connected
2. Go to Grafana → Configuration → Data Sources
3. Test the connection to Prometheus
4. Ensure your query syntax is correct

### Issue: AlertManager Not Sending Alerts

**Solution:**
1. Check AlertManager configuration:
   ```bash
   kubectl get secret -n monitoring alertmanager-kube-stack-prometheus -o yaml
   ```

2. Verify AlertManager is running:
   ```bash
   kubectl get pods -n monitoring | grep alertmanager
   ```

3. Check Prometheus alert status:
   ```bash
   kubectl port-forward -n monitoring svc/kube-stack-prometheus-prometheus 9090:9090
   # Visit http://localhost:9090/alerts
   ```

---

## 🎯 Monitoring Best Practices

### 1. Set Appropriate Scrape Intervals
```yaml
# Balance between data freshness and storage
interval: 30s  # Default is good for most use cases
```

### 2. Define Clear Alert Thresholds
- CPU: Alert at 80%, critical at 90%
- Memory: Alert at 80%, critical at 90%
- Error Rate: Alert at 5%, critical at 10%

### 3. Create Team Dashboards
- **Platform Team Dashboard:** Cluster health, node utilization
- **Application Team Dashboard:** Application-specific metrics
- **Business Dashboard:** SLA metrics, revenue-impacting metrics

### 4. Regular Dashboard Maintenance
- Review dashboards quarterly
- Remove unused panels
- Update thresholds based on trends

---

## 📈 Next Steps & Recommendations

### Immediate Actions
1. ✅ Install Prometheus + Grafana stack
2. ✅ Expose Grafana and log in
3. ✅ Enable metrics in Spring Boot
4. ✅ Create first custom dashboard

### Future Enhancements
- **Distributed Tracing:** Add Jaeger for request tracing
- **Logging:** Integrate ELK (Elasticsearch, Logstash, Kibana)
- **Cost Monitoring:** Track resource usage and costs
- **SLO Tracking:** Monitor Service Level Objectives
- **Multi-Cluster Monitoring:** Monitor multiple EKS clusters

---

## 🔗 Useful Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [Micrometer Documentation](https://micrometer.io/)
- [Spring Boot Actuator](https://spring.io/guides/gs/actuator-service/)
- [Kube-Stack-Prometheus Helm Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-stack-prometheus)

---

## ✅ Monitoring Verification Checklist

Before considering your monitoring complete, verify:

- [ ] Prometheus pod is running in monitoring namespace
- [ ] Grafana pod is running in monitoring namespace
- [ ] Grafana is accessible via LoadBalancer URL
- [ ] Can log in to Grafana with admin credentials
- [ ] Micrometer dependency added to `pom.xml`
- [ ] Metrics endpoint exposed in `application.properties`
- [ ] ServiceMonitor created and deployed
- [ ] Prometheus scraping Spring Boot metrics (check targets)
- [ ] At least one custom dashboard created
- [ ] Alert rules deployed (optional but recommended)

---

## 🎉 Summary

Your enterprise-grade monitoring setup now provides:

1. ✅ **Real-time Metrics:** Prometheus collects metrics every 30 seconds
2. ✅ **Beautiful Dashboards:** Grafana visualizes all important metrics
3. ✅ **Application Insights:** Spring Boot metrics reveal app behavior
4. ✅ **Alerting:** Automatic notifications for critical issues
5. ✅ **Historical Data:** Time-series storage for trend analysis
6. ✅ **Scalability:** Works with single or multiple EKS clusters

**Your team now has complete visibility into your Spring Boot application and EKS cluster!** 📊🚀
