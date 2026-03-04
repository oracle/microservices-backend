---
title: Deployment Overview
sidebar_position: 0
---

## Deploying Applications to Oracle Backend for Microservices and AI

This guide outlines the steps to build, deploy, and expose an application on Oracle Backend for Microservices and AI (OBaaS).

### Deployment Steps

| Step | Description | Details |
|------|-------------|---------|
| 1 | **Create container repositories** | Set up a repository per microservice in your container registry (OCIR, ECR, ACR, etc.). |
| 2 | **Build and push images** | Use Maven and Eclipse JKube to build JARs, create container images, and push to the registry. |
| 3 | **Create database secrets** | Create Kubernetes secrets with privileged and per-service database credentials. |
| 4 | **Deploy with Helm** | Install each service using the `obaas-sample-app` Helm chart with a per-service `values.yaml`. |
| 5 | **Create API gateway routes** | Configure Apache APISIX routes to expose services externally via Eureka discovery. |

### Detailed Guide

- [Deploying an Application to OBaaS](./deploy.md) — Full step-by-step walkthrough with commands and configuration examples
