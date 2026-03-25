# 🗄️ Database Migrations in GitOps: Flyway & Liquibase Integration

## Overview

**Integrating Database Migrations** (like Liquibase or Flyway) is the final bridge between code and data. In a GitOps world, you never want to manually run SQL scripts against your production database. Instead, your Spring Boot app should "carry" its schema changes and apply them automatically as soon as the Pod starts up.

This ensures:
- ✅ **Version Control:** SQL changes live in Git alongside Java code
- ✅ **Safety:** Failed deployments roll back both code AND database changes together
- ✅ **Automation:** No manual DBA intervention needed
- ✅ **Traceability:** Full audit trail of every schema change
- ✅ **Repeatability:** Same migrations work on dev, staging, and production

---

## Architecture: GitOps with Database Migrations

```
Developer
    ↓ (commits SQL + code to Git)
GitHub Repository
    ├── src/main/java/...          (Java code)
    ├── src/main/resources/db/migration/  (SQL scripts)
    └── pom.xml                    (Flyway dependency)
    ↓ (GitHub Actions)
Build & Push Docker Image
    ↓ (image includes SQL files)
Update Deployment YAML
    ↓ (Argo CD detects change)
Deploy New Version to EKS
    ↓ (Pod starts up)
Spring Boot Initializes
    ↓ (Flyway runs automatically)
Database Migrations Execute
    ↓
Pod is Ready with Updated Schema ✅
```

---

## Prerequisites

Before starting, ensure you have:

- A Spring Boot application (Java 8+)
- PostgreSQL, MySQL, or H2 database
- AWS RDS instance (recommended for production)
- EKS cluster with proper networking to RDS
- Maven build tool
- Git repository with application code

---

## Part 1: Why Database Migrations Matter in GitOps

### 1.1 Problem Without Migrations

```
Developer adds a new feature that needs a users.email column
↓
Code gets deployed to production
↓
App crashes: "Column 'email' doesn't exist"
↓
Manual DBA intervention required
↓
Email goes out: "Production outage in progress"
↓
Time to fix: 30+ minutes
↓
Cost: Angry customers + reputation damage 😱
```

### 1.2 Solution With Migrations (Flyway)

```
Developer adds users.email column
↓
Creates V2__add_email_column.sql in Git
↓
Commits both code AND migration
↓
GitHub Actions builds and deploys
↓
Argo CD syncs deployment
↓
Pod starts → Spring Boot → Flyway runs V2 → Column created
↓
App starts → No errors
↓
Everything works automatically ✅
```

### 1.3 Why Flyway Over Liquibase?

| Feature | Flyway | Liquibase |
|---------|--------|-----------|
| **Learning Curve** | Very easy (just SQL) | Steeper (XML/YAML) |
| **Language** | SQL only | SQL, XML, YAML, JSON |
| **Git-friendly** | Simple files | Verbose config files |
| **Cloud-native** | Excellent | Good |
| **Recommendation** | 👍 Start here | Use if need XML/YAML |

---

## Part 2: Setting Up Flyway in Spring Boot

### 2.1 Add Dependencies to pom.xml

Add the Flyway dependencies to your `pom.xml`:

```xml
<project>
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>spring-boot-kubernetes</artifactId>
    <version>1.0.0</version>
    
    <dependencies>
        <!-- Existing Spring Boot dependencies -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
        
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-jpa</artifactId>
        </dependency>
        
        <!-- Database Driver (choose one) -->
        <dependency>
            <groupId>org.postgresql</groupId>
            <artifactId>postgresql</artifactId>
            <scope>runtime</scope>
        </dependency>
        <!-- OR for MySQL:
        <dependency>
            <groupId>com.mysql</groupId>
            <artifactId>mysql-connector-java</artifactId>
            <scope>runtime</scope>
        </dependency>
        -->
        
        <!-- ADD THESE FOR FLYWAY -->
        <dependency>
            <groupId>org.flywaydb</groupId>
            <artifactId>flyway-core</artifactId>
        </dependency>
        
        <dependency>
            <groupId>org.flywaydb</groupId>
            <artifactId>flyway-database-postgresql</artifactId>
        </dependency>
        <!-- For MySQL, use:
        <dependency>
            <groupId>org.flywaydb</groupId>
            <artifactId>flyway-mysql</artifactId>
        </dependency>
        -->
        
        <!-- Testing -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>
    
    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>
</project>
```

### 2.2 Create Database Migration Scripts

Flyway expects migration scripts in: `src/main/resources/db/migration/`

**Naming Convention:** `V{number}__{description}.sql`

Example structure:
```
src/main/resources/db/migration/
├── V1__init.sql                         # First migration
├── V2__add_users_table.sql              # Second migration
├── V3__add_email_column.sql             # Third migration
└── V4__add_indexes.sql                  # Fourth migration
```

**File: V1__init.sql** (Initial schema)
```sql
-- Create tables for the initial schema
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS posts (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Create indexes for better performance
CREATE INDEX idx_posts_user_id ON posts(user_id);
CREATE INDEX idx_users_username ON users(username);
```

**File: V2__add_email_column.sql** (Add new column)
```sql
-- Add email column to users table
ALTER TABLE users ADD COLUMN email VARCHAR(255);

-- Create unique constraint on email
ALTER TABLE users ADD CONSTRAINT uq_users_email UNIQUE(email);

-- Create index for email lookups
CREATE INDEX idx_users_email ON users(email);
```

**File: V3__add_phone_column.sql** (Another change)
```sql
-- Add phone number to users
ALTER TABLE users ADD COLUMN phone_number VARCHAR(20);

-- Add last_login tracking
ALTER TABLE users ADD COLUMN last_login_at TIMESTAMP;
```

**File: V4__add_posts_metadata.sql** (Extend existing tables)
```sql
-- Add metadata to posts
ALTER TABLE posts ADD COLUMN updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE posts ADD COLUMN likes_count INT DEFAULT 0;
ALTER TABLE posts ADD COLUMN comments_count INT DEFAULT 0;

-- Add views counter to posts
ALTER TABLE posts ADD COLUMN view_count INT DEFAULT 0;
```

### 2.3 Update application.properties

Enable Flyway and configure database connection:

```properties
# ===== FLYWAY CONFIGURATION =====
spring.flyway.enabled=true
spring.flyway.locations=classpath:db/migration
spring.flyway.baseline-on-migrate=false
# Clean database on startup (only for dev/testing!)
# spring.flyway.clean-disabled=false

# ===== DATABASE CONNECTION =====
# Use environment variables for secrets (injected by Kubernetes)
spring.datasource.url=jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}
spring.datasource.username=${DB_USERNAME}
spring.datasource.password=${DB_PASSWORD}
spring.datasource.driver-class-name=org.postgresql.Driver

# Connection pool settings
spring.datasource.hikari.maximum-pool-size=10
spring.datasource.hikari.minimum-idle=5
spring.datasource.hikari.connection-timeout=30000

# ===== JPA/HIBERNATE =====
spring.jpa.hibernate.ddl-auto=validate
spring.jpa.show-sql=false
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.PostgreSQLDialect

# ===== LOGGING =====
logging.level.org.flywaydb=INFO
logging.level.org.flywaydb.core.internal.command=DEBUG
```

### 2.4 Alternative: application.yml Format

If you prefer YAML:

```yaml
spring:
  flyway:
    enabled: true
    locations: classpath:db/migration
    baseline-on-migrate: false
  
  datasource:
    url: jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}
    username: ${DB_USERNAME}
    password: ${DB_PASSWORD}
    driver-class-name: org.postgresql.Driver
    hikari:
      maximum-pool-size: 10
      minimum-idle: 5
      connection-timeout: 30000
  
  jpa:
    hibernate:
      ddl-auto: validate
    show-sql: false
    properties:
      hibernate:
        dialect: org.hibernate.dialect.PostgreSQLDialect

logging:
  level:
    org.flywaydb: INFO
    org.flywaydb.core.internal.command: DEBUG
```

### 2.5 Create a JPA Entity to Use the Schema

Create a Spring Boot entity that matches your schema:

```java
package com.example.entity;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "users")
public class User {
    
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Integer id;
    
    @Column(nullable = false, unique = true, length = 255)
    private String username;
    
    @Column(unique = true, length = 255)
    private String email;
    
    @Column(length = 20)
    private String phoneNumber;
    
    @Column(name = "created_at")
    private LocalDateTime createdAt;
    
    @Column(name = "last_login_at")
    private LocalDateTime lastLoginAt;
    
    // Constructors, getters, setters
    public User() {}
    
    public User(String username, String email) {
        this.username = username;
        this.email = email;
    }
    
    public Integer getId() { return id; }
    public void setId(Integer id) { this.id = id; }
    
    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }
    
    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }
    
    public String getPhoneNumber() { return phoneNumber; }
    public void setPhoneNumber(String phoneNumber) { this.phoneNumber = phoneNumber; }
    
    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }
    
    public LocalDateTime getLastLoginAt() { return lastLoginAt; }
    public void setLastLoginAt(LocalDateTime lastLoginAt) { this.lastLoginAt = lastLoginAt; }
}
```

### 2.6 Test Locally

```bash
# Start PostgreSQL locally (using Docker)
docker run -d \
  --name postgres \
  -e POSTGRES_DB=mydb \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=password \
  -p 5432:5432 \
  postgres:15

# Set environment variables
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=mydb
export DB_USERNAME=postgres
export DB_PASSWORD=password

# Run Spring Boot application
mvn spring-boot:run

# Check logs for Flyway execution
# You should see: "Successfully validated 4 migrations (execution time 45ms)"
```

---

## Part 3: Handling Database Credentials in Kubernetes

You should **never hardcode database passwords** in your Git repository. Instead, use Kubernetes Secrets.

### 3.1 Create a Kubernetes Secret

**Option 1: Create with kubectl**

```bash
# Create the secret
kubectl create secret generic db-credentials \
  --from-literal=host=my-rds-instance.c9akciq32.us-east-1.rds.amazonaws.com \
  --from-literal=port=5432 \
  --from-literal=name=mydb \
  --from-literal=username=dbadmin \
  --from-literal=password='MySecurePassword123!' \
  -n default

# Verify it was created
kubectl get secret db-credentials -o yaml
```

**Option 2: Create with YAML manifest (k8s/secret.yaml)**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
  namespace: default
type: Opaque
stringData:
  host: my-rds-instance.c9akciq32.us-east-1.rds.amazonaws.com
  port: "5432"
  name: mydb
  username: dbadmin
  password: MySecurePassword123!
```

Apply the secret:
```bash
kubectl apply -f k8s/secret.yaml
```

**⚠️ Warning:** Never commit the secret YAML with actual passwords to Git. Use one of these approaches:

1. **SealedSecrets:** Encrypt secrets before committing
2. **External Secrets Operator:** Fetch secrets from AWS Secrets Manager
3. **ArgoCD Secrets Plugin:** Use a plugin to inject secrets at deploy time

### 3.2 Inject Secrets into Deployment

Update your `k8s/deployment.yaml` to inject database credentials:

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
        
        # INJECT DATABASE CREDENTIALS FROM SECRET
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
        
        # Spring Boot will read these env vars automatically
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        
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

### 3.3 Verify Secret Injection

```bash
# Apply deployment
kubectl apply -f k8s/deployment.yaml

# Check if Pod started successfully
kubectl get pods

# View environment variables in running Pod
kubectl exec -it <pod-name> -- env | grep DB_

# Check logs for Flyway execution
kubectl logs <pod-name> | grep -i flyway
```

---

## Part 4: Setting Up AWS RDS for Production

### 4.1 Create RDS Instance (if not already done)

```bash
# Using AWS CLI
aws rds create-db-instance \
  --db-instance-identifier spring-boot-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 15.3 \
  --master-username dbadmin \
  --master-user-password 'MySecurePassword123!' \
  --allocated-storage 20 \
  --storage-type gp2 \
  --backup-retention-period 7 \
  --multi-az \
  --publicly-accessible false
```

### 4.2 Configure Security Groups

```bash
# Get RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier spring-boot-db \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

# Get RDS security group
RDS_SG=$(aws rds describe-db-instances \
  --db-instance-identifier spring-boot-db \
  --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text)

# Get EKS security group
EKS_SG=$(aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=eks-node-sg" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

# Allow EKS nodes to access RDS
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG \
  --protocol tcp \
  --port 5432 \
  --source-security-group-id $EKS_SG
```

### 4.3 Update Kubernetes Secret with RDS Details

```bash
# Get RDS endpoint
RDS_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier spring-boot-db \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

# Create secret with RDS endpoint
kubectl create secret generic db-credentials \
  --from-literal=host=$RDS_HOST \
  --from-literal=port=5432 \
  --from-literal=name=mydb \
  --from-literal=username=dbadmin \
  --from-literal=password='MySecurePassword123!' \
  -n default
```

---

## Part 5: Managing Multiple Environments

### 5.1 Dev Environment (with flyway.clean)

```properties
# application-dev.properties
spring.flyway.enabled=true
spring.flyway.clean-disabled=false  # Allow cleaning for dev
spring.datasource.url=jdbc:postgresql://localhost:5432/mydb_dev
spring.datasource.username=dev_user
spring.datasource.password=dev_password
```

### 5.2 Staging Environment

```properties
# application-staging.properties
spring.flyway.enabled=true
spring.flyway.clean-disabled=true  # Never clean in staging
spring.datasource.url=jdbc:postgresql://staging-rds.amazonaws.com:5432/mydb_staging
spring.datasource.username=${DB_USERNAME}
spring.datasource.password=${DB_PASSWORD}
```

### 5.3 Production Environment

```properties
# application-prod.properties
spring.flyway.enabled=true
spring.flyway.clean-disabled=true  # Never clean in production
spring.flyway.validate-on-migrate=true  # Validate migrations
spring.datasource.url=jdbc:postgresql://prod-rds.amazonaws.com:5432/mydb
spring.datasource.username=${DB_USERNAME}
spring.datasource.password=${DB_PASSWORD}
spring.datasource.hikari.maximum-pool-size=20
spring.datasource.hikari.minimum-idle=10
```

### 5.4 Launch Application with Profile

```bash
# For local development
java -jar app.jar --spring.profiles.active=dev

# For staging
java -jar app.jar --spring.profiles.active=staging

# For production (via Kubernetes env var)
# env:
# - name: SPRING_PROFILES_ACTIVE
#   value: "prod"
```

---

## Part 6: GitOps Workflow with Database Migrations

### 6.1 Complete Development Workflow

```bash
# Step 1: Developer makes code changes
git checkout -b feature/add-email-column

# Step 2: Create migration file
cat > src/main/resources/db/migration/V2__add_email_column.sql <<EOF
ALTER TABLE users ADD COLUMN email VARCHAR(255);
CREATE UNIQUE INDEX idx_users_email ON users(email);
EOF

# Step 3: Update Java entity to use new column
# (edit src/main/java/entity/User.java)

# Step 4: Test locally
export DB_HOST=localhost DB_PORT=5432 DB_NAME=mydb DB_USERNAME=postgres DB_PASSWORD=password
mvn clean test
mvn spring-boot:run

# Step 5: Verify migration ran
# Check logs: "Successfully validated 2 migrations (execution time 45ms)"

# Step 6: Commit both code and migration
git add src/main/java/entity/User.java src/main/resources/db/migration/V2__add_email_column.sql
git commit -m "feat: add email field to users

- Add email column to users table
- Add unique constraint on email
- Update User entity with email field
- Migration: V2__add_email_column.sql"

# Step 7: Push and create Pull Request
git push origin feature/add-email-column
# Create PR on GitHub
```

### 6.2 Automated CI/CD Pipeline

Your `.github/workflows/ci.yml` should:

```yaml
name: CI Pipeline

on:
  push:
    branches: [main]

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_DB: testdb
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Set up JDK 21
      uses: actions/setup-java@v3
      with:
        java-version: '21'
        distribution: 'temurin'
    
    - name: Run tests (includes Flyway migration)
      env:
        DB_HOST: localhost
        DB_PORT: 5432
        DB_NAME: testdb
        DB_USERNAME: test
        DB_PASSWORD: test
      run: mvn clean test
    
    - name: Build application
      run: mvn clean package -DskipTests
    
    - name: Build and push Docker image
      # ... (existing docker build/push)
```

---

## Part 7: Best Practices for Database Migrations

### 7.1 Migration Naming and Organization

```
db/migration/
├── V1__init_schema.sql                    # Initial schema
├── V2__add_audit_table.sql               # Add new table
├── V3__add_indexes.sql                   # Performance improvements
├── V4__alter_users_add_email.sql         # Add new column
├── V5__add_constraints.sql               # Add constraints
└── V6__create_posts_table.sql            # New feature
```

**Naming convention:**
- Use `V` prefix for versioned migrations
- Number sequentially: V1, V2, V3, ...
- Use double underscore `__` separator
- Use snake_case for description
- Be descriptive: `V5__add_constraints.sql` not `V5__update.sql`

### 7.2 Safe Migration Practices

**✅ DO:**
```sql
-- Use IF NOT EXISTS to make migrations idempotent
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) NOT NULL
);

-- Add columns with default values
ALTER TABLE users ADD COLUMN email VARCHAR(255) DEFAULT '';

-- Create indexes (usually safe)
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
```

**❌ DON'T:**
```sql
-- Don't drop tables without backup
DROP TABLE users;  -- DANGER!

-- Don't remove columns without backup
ALTER TABLE users DROP COLUMN username;  -- DANGER!

-- Don't make breaking changes without migration path
ALTER TABLE users ALTER COLUMN email SET NOT NULL;  -- Use 2-phase approach
```

### 7.3 Handling Large Tables

For large table migrations, use a two-step approach:

**Step 1: Create new column as nullable (V3)**
```sql
ALTER TABLE large_table ADD COLUMN new_column VARCHAR(255);
```

**Step 2: Populate data in scheduled job or batch**
```java
// In a separate scheduled task
@Scheduled(fixedRate = 60000)
public void populateNewColumn() {
    repository.updateNullNewColumns();
}
```

**Step 3: Add NOT NULL constraint later (V4)**
```sql
-- After data is populated
ALTER TABLE large_table ALTER COLUMN new_column SET NOT NULL;
```

### 7.4 Testing Migrations

```bash
# Test migrations locally
mvn test

# Test migration rollback (for some databases)
# Flyway doesn't support undo, so have a V{n}__rollback.sql if needed

# Test on staging before production
# Deploy to staging first, verify migrations work, then deploy to prod

# Keep migration execution logs
# Check: kubectl logs <pod-name> | grep -i flyway
```

---

## Part 8: Monitoring and Troubleshooting

### 8.1 Check Flyway Migration Status

```bash
# View application logs for Flyway execution
kubectl logs <pod-name> | grep -i flyway

# Expected output:
# Flyway 9.22.3 by Redgate
# Database: jdbc:postgresql://rds.amazonaws.com:5432/mydb (PostgreSQL 15.3)
# Schema history table "public.flyway_schema_history" does not exist yet.
# Successfully validated 6 migrations (execution time 45ms)
# Creating Schema history table: "public.flyway_schema_history"
# Current version of schema (None): << Empty schema
# Migrating schema to version 1 - init schema
# Successfully applied 1 migration to schema (execution time 234ms)
# Migrating schema to version 2 - add email column
# Successfully applied 1 migration to schema (execution time 145ms)
# ...
```

### 8.2 Query Migration History

```sql
-- Connect to your database and check migration history
SELECT * FROM flyway_schema_history ORDER BY installed_rank;

-- Output:
-- | installed_rank | version | description | type | script | checksum | installed_by | installed_on | execution_time | success |
-- | 1 | 1 | init schema | SQL | V1__init_schema.sql | -123456789 | postgres | 2025-03-25 10:30:45 | 234 | t |
-- | 2 | 2 | add email column | SQL | V2__add_email_column.sql | -987654321 | postgres | 2025-03-25 10:30:46 | 145 | t |
```

### 8.3 Troubleshooting: Pod Won't Start

**Error: "No matching implementation of interface found"**

```
ERROR in org.flywaydb.core.internal.scanner.classpath.ClassPathScanner
No matching implementation of interface DatabaseType found for name 'postgresql'
```

**Solution:** Add the correct Flyway database dependency:
```xml
<dependency>
    <groupId>org.flywaydb</groupId>
    <artifactId>flyway-database-postgresql</artifactId>
</dependency>
```

### 8.4 Troubleshooting: Migration Validation Failed

**Error: "Checksum mismatch"**

```
Flyway validation failed. Migration checksum mismatch for migration version 1
Expected: 12345678
Actual: 87654321
```

**Cause:** Migration file was modified after execution.

**Solution:**
1. **Never modify** a migration that was already executed in production
2. Create a **new migration** to fix the issue:
   ```sql
   -- V3__fix_issue_from_v1.sql
   -- Fix the issue that V1 should have handled
   ```

### 8.5 Troubleshooting: Migration Never Runs

**Problem:** Pod starts but migration doesn't execute.

**Check:**
```bash
# Verify Flyway is enabled in properties
# spring.flyway.enabled=true

# Check pod environment variables
kubectl exec <pod-name> -- env | grep SPRING

# Check logs for Spring Boot startup
kubectl logs <pod-name> | head -100

# Verify database connection works
kubectl exec <pod-name> -- /bin/bash
psql -h $DB_HOST -U $DB_USERNAME -d $DB_NAME -c "SELECT 1"
```

---

## Part 9: Advanced Configurations

### 9.1 Flyway Callbacks (Optional)

Execute custom logic before/after migrations:

```java
package com.example.config;

import org.flywaydb.core.api.callback.Context;
import org.flywaydb.core.api.callback.Event;
import org.flywaydb.core.api.callback.Callback;
import org.springframework.stereotype.Component;

@Component
public class MigrationCallback implements Callback {
    
    @Override
    public void handle(Event event, Context context) {
        switch(event) {
            case BEFORE_MIGRATE:
                System.out.println("Starting database migration...");
                break;
            case AFTER_MIGRATE:
                System.out.println("Database migration completed successfully!");
                break;
            case AFTER_MIGRATE_ERROR:
                System.out.println("Database migration failed!");
                break;
        }
    }
    
    @Override
    public boolean supports(Event event, Context context) {
        return true;  // Handle all events
    }
    
    @Override
    public boolean canHandleInTransaction(Event event, Context context) {
        return true;
    }
    
    @Override
    public Integer getOrder() {
        return 0;
    }
}
```

### 9.2 Placeholder Replacement

Use placeholders in migrations:

```properties
# application.properties
flyway.placeholders.app_version=1.0
flyway.placeholders.environment=production
```

In migration:
```sql
-- V1__init.sql
INSERT INTO app_config (version, environment) 
VALUES ('${app_version}', '${environment}');
```

### 9.3 Undo Migrations (if supported)

For databases that support undo:

```sql
-- V1__init.sql (forward)
CREATE TABLE users (id SERIAL PRIMARY KEY);

-- U1__init.sql (undo - Flyway Pro only)
DROP TABLE users;
```

---

## 📁 Complete Project Structure

Your project should now have:

```
spring-boot-kubernetes/
├── .github/
│   └── workflows/
│       └── ci.yml                      # CI pipeline with tests
├── k8s/
│   ├── deployment.yaml                 # With DB env vars
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── secret.yaml                     # DB credentials (don't commit to Git!)
│   ├── issuer.yaml
│   ├── service-monitor.yaml
│   ├── hpa.yaml
│   ├── quota.yaml
│   └── limitrange.yaml
├── src/main/
│   ├── java/
│   │   └── com/example/
│   │       ├── entity/
│   │       │   └── User.java           # JPA entity
│   │       ├── repository/
│   │       │   └── UserRepository.java
│   │       ├── controller/
│   │       │   └── UserController.java
│   │       └── Application.java
│   └── resources/
│       ├── db/migration/                # 🆕 Flyway migrations
│       │   ├── V1__init.sql
│       │   ├── V2__add_email_column.sql
│       │   ├── V3__add_phone_column.sql
│       │   └── V4__add_posts_metadata.sql
│       ├── application.properties       # Default profile
│       ├── application-dev.properties
│       ├── application-staging.properties
│       └── application-prod.properties
├── Dockerfile
├── pom.xml                              # With Flyway dependency
└── README.md
```

---

## 🔄 Complete GitOps Deployment Flow

```
1. Developer commits code + migration
   ↓
2. GitHub Actions runs tests
   - Flyway applies migrations to test database
   - Tests pass ✅
   ↓
3. Build Docker image with code + migrations
   ↓
4. Push image to ECR
   ↓
5. Update deployment.yaml image tag
   ↓
6. Argo CD detects change in Git
   ↓
7. Deploy new version to EKS
   ↓
8. Old Pod terminates
   ↓
9. New Pod starts
   ↓
10. Spring Boot initializes
   ↓
11. Flyway automatically runs migrations
    - Validates checksums
    - Applies any new migrations
    - Updates flyway_schema_history table
   ↓
12. Application is ready ✅
   ↓
13. Zero downtime deployment with schema changes!
```

---

## ✅ Database Migration Verification Checklist

Before considering setup complete, verify:

- [ ] Flyway dependency added to pom.xml
- [ ] Migration files created in `src/main/resources/db/migration/`
- [ ] Migration files follow naming convention `V{n}__{description}.sql`
- [ ] application.properties configured with Flyway settings
- [ ] `spring.flyway.enabled=true`
- [ ] Database connection properties reference environment variables
- [ ] JPA entities created to match migration schema
- [ ] Kubernetes Secret created with DB credentials
- [ ] Deployment.yaml injects DB credentials as env vars
- [ ] Local testing successful with migrations applied
- [ ] Migration history table created and visible in database
- [ ] CI pipeline includes database tests with Flyway
- [ ] Multiple migration versions tested successfully
- [ ] Rollback strategy documented (if needed)
- [ ] Different properties for dev/staging/prod profiles

---

## 📚 Common Migration Scenarios

### Scenario 1: Add New Table
```sql
-- V5__add_products_table.sql
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    price DECIMAL(10, 2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_products_name ON products(name);
```

### Scenario 2: Add Column to Existing Table
```sql
-- V6__add_description_to_products.sql
ALTER TABLE products ADD COLUMN description TEXT;
CREATE INDEX idx_products_description ON products(description);
```

### Scenario 3: Add Constraints
```sql
-- V7__add_price_constraint.sql
ALTER TABLE products 
ADD CONSTRAINT chk_price_positive CHECK (price > 0);
```

### Scenario 4: Rename Column
```sql
-- V8__rename_product_description.sql
ALTER TABLE products 
RENAME COLUMN description TO product_description;
```

---

## 🔗 Useful Resources

- [Flyway Documentation](https://flywaydb.org/documentation)
- [Flyway Best Practices](https://flywaydb.org/getstarted/how)
- [Spring Boot + Flyway Integration](https://spring.io/guides/gs/accessing-data-mysql/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Database Migrations Best Practices](https://wiki.postgresql.org/wiki/Migration_tools)

---

## 🎉 Summary

Your production-ready database migration setup now provides:

1. ✅ **Version Control:** All schema changes in Git with code
2. ✅ **Automation:** Migrations run automatically on Pod startup
3. ✅ **Safety:** Rollback-safe with full history tracking
4. ✅ **GitOps:** Complete CI/CD pipeline with database changes
5. ✅ **Secrets Management:** Database credentials never in Git
6. ✅ **Multi-Environment:** Different configurations per environment
7. ✅ **Testing:** Migrations validated before production deployment
8. ✅ **Auditability:** Complete migration history in database

**Your Spring Boot app can now manage its own schema alongside code deployments!** 🚀🗄️
