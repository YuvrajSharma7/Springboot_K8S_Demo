# End-to-End GitOps Deployment Guide: Spring Boot to AWS EKS

This document details the complete setup, configuration, and troubleshooting steps for a GitOps pipeline that builds a Spring Boot application via GitHub Actions, pushes the image to Amazon ECR, and automatically deploys it to an Amazon EKS cluster using Argo CD.

## 🔄 Process Flow Architecture

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Git as GitHub Repo (main)
    participant CI as GitHub Actions
    participant ECR as Amazon ECR
    participant Argo as Argo CD
    participant EKS as Amazon EKS

    Dev->>Git: 1. Push Spring Boot Code
    Git->>CI: 2. Trigger ci.yml Workflow
    CI->>CI: 3. Build & Package (Maven/Docker)
    CI->>ECR: 4. Direct Login & Push Image
    CI->>Git: 5. sed -i Update deployment.yaml & git push
    loop Every 3 Minutes
        Argo->>Git: 6. Poll for Manifest Changes
    end
    Argo->>ECR: 7. Pull New Image Tag
    Argo->>EKS: 8. Apply Updates to Cluster
    EKS-->>Dev: 9. App Available via LoadBalancer URL