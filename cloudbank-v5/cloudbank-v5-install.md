# CloudBank v5 Installation Guide

## Overview

CloudBank v5 is a reference application demonstrating cloud-native microservices architecture using Oracle Backend as a Service (OBaaS). It consists of six interconnected services:

| Service | Purpose |
|---------|---------|
| **account** | Manages accounts, balances, and transactions (LRA participant) |
| **customer** | Handles customer profiles (Oracle ADB 23ai) |
| **transfer** | Orchestrates money transfers (LRA coordinator, Saga pattern) |
| **checks** | Processes check deposits asynchronously (Oracle AQ, JMS) |
| **creditscore** | Provides credit scoring (stateless REST) |
| **testrunner** | Test harness for workflows (AQ producer) |

**Technology Stack:** Spring Boot 3.4, Oracle ADB, MicroTx, Oracle AQ, OpenTelemetry

---

## Overview of Installation

The installation process consists of five main steps:

| Step | Script | Description |
|------|--------|-------------|
| 1 | `1-oci_repos.sh` | Create container repositories in OCI Registry |
| 2 | `2-images_build_push.sh` | Build and push microservice container images |
| 3 | `3-k8s_db_secrets.sh` | Create Kubernetes secrets for database credentials |
| 4 | `4-deploy_all_services.sh` | Deploy all services using Helm |
| 5 | `5-apisix_create_routes.sh` | Create APISIX API Gateway routes |

Each step must be completed in order, as later steps depend on earlier ones.

**Time Breakdown:**

| Step | Time Estimate |
|------|---------------|
| Step 1: Create repositories | ~1 minute |
| Step 2: Build and push images | ~15-20 minutes |
| Step 3: Create secrets | ~1 minute |
| Step 4: Deploy services | ~5-10 minutes |
| Step 5: Create routes | ~1 minute |
| **Total** | **~25-35 minutes** |

---

## Prerequisites

### Required Software
- **Oracle Backend as a Service (OBaaS)** installed
- **Oracle Autonomous Database** (23ai or 19c)
- **Java 21**, **Maven 3.6+**
- **kubectl** connected to your cluster
- **Docker** or compatible runtime (Rancher Desktop, Docker Desktop)
- **OCI CLI** configured (if using OCI Registry)

### Verify Prerequisites

```bash
./check_prereqs.sh
```

Or manually:
```bash
java --version          # Should be 21
mvn --version           # Should be 3.6+
kubectl get nodes       # Should show cluster nodes
docker ps               # Should not error
oci --version           # If using OCI Registry
```

### Important Assumptions

CloudBank must be installed in the **same namespace** as OBaaS. Services require access to OBaaS components (Eureka, APISIX, database secrets) within the same namespace.

---

## Quick Reference

**⚠️ Note:**: For experienced users. All scripts support `--help` for additional options.

```bash
# Step 1: Create OCI container repositories
./1-oci_repos.sh -c <compartment_name> -p <prefix>

# Step 2: Build and push images
export DOCKER_HOST=unix:///Users/$USER/.rd/docker.sock  # Rancher Desktop
docker login <region>.ocir.io -u '<tenancy>/<username>'
./2-images_build_push.sh -p <prefix>

# Step 3: Create database secrets (can run while Step 2 is building)
./3-k8s_db_secrets.sh -n <namespace> -d <dbname>

# Step 4: Deploy services
./4-deploy_all_services.sh -n <namespace> -d <dbname> -p <prefix>

# Step 5: Create APISIX routes
./5-apisix_create_routes.sh -n <namespace>

# Verify
kubectl get pods -n <namespace>
```

**Example values:**

| Placeholder | Example Value |
|-------------|---------------|
| `<compartment_name>` | `obaas-compartment` |
| `<namespace>` | `obaas-dev` |
| `<dbname>` | `cbankdb` |
| `<prefix>` | `cloudbank-v5` |
| `<region>` | `us-phoenix-1` |
| `<tenancy>` | `mytenancy` |

---

## Step 1: Create Container Repositories

**Time estimate:** ~1 minute

**What this script does:**
- Validates OCI CLI is configured
- Looks up the compartment OCID from the compartment name
- Retrieves the tenancy namespace from OCI
- Creates 6 container repositories (account, customer, transfer, checks, creditscore, testrunner)
- Repositories are public by default (use `--private` for private repos)
- Use `--delete` to remove repositories during cleanup

**Command:**
```bash
./1-oci_repos.sh -c <compartment_name> -p <prefix>
```

**Example:**
```bash
./1-oci_repos.sh -c obaas-compartment -p cloudbank-v5
```

**Verify:**
```bash
oci artifacts container repository list --compartment-id <OCID> \
  --query 'data.items[*].{"name":"display-name"}' --output table
```

---

## Step 2: Build and Push Images

**Time estimate:** ~15-20 minutes

**What this script does:**
- Validates prerequisites (Java, Maven, Docker, registry connectivity)
- Auto-detects OCI Registry from OCI CLI configuration (or uses provided registry)
- Builds shared dependencies (buildtools, parent pom, common module)
- Builds all 6 microservice JARs using Maven
- Creates container images using JKube
- Pushes images to the container registry
- Supports parallel builds with `-j` flag

### 2.1 Configure Docker

```bash
# Rancher Desktop (macOS)
export DOCKER_HOST=unix:///Users/$USER/.rd/docker.sock

# Docker Desktop / Linux
export DOCKER_HOST=unix:///var/run/docker.sock
```

### 2.2 Authenticate with Registry

**OCI Registry:**
```bash
docker login <region>.ocir.io -u '<tenancy>/<username>'
```

**Example:**
```bash
docker login us-phoenix-1.ocir.io -u 'mytenancy/oracleidentitycloudservice/john.doe@example.com'
# Enter OCI Auth Token when prompted
```

**Docker Hub:**
```bash
docker login -u <username>
```

### 2.3 Build and Push

**Command:**
```bash
./2-images_build_push.sh -p <prefix>
```

**Example:**
```bash
./2-images_build_push.sh -p cloudbank-v5
```

Use `-j 4` for parallel builds on multi-core machines.

---

## Step 3: Create Database Secrets

**Time estimate:** ~1 minute

**What this script does:**
- Validates the privileged secret `<dbname>-db-priv-authn` exists
- Reads the TNS service name from the privileged secret
- Generates Oracle-compatible passwords for each service account
- Creates Kubernetes secrets with username, password, and service keys
- Usernames are uppercase (Oracle requirement)

**Prerequisite:** The privileged secret `<dbname>-db-priv-authn` must exist (created during OBaaS setup). If your secret has a different name, use the `-s` flag to specify it.

**Verify it exists:**
```bash
kubectl get secret <dbname>-db-priv-authn -n <namespace>
```

**Command:**
```bash
./3-k8s_db_secrets.sh -n <namespace> -d <dbname>
# Or with a custom privileged secret name:
./3-k8s_db_secrets.sh -n <namespace> -d <dbname> -s <secret-name>
```

**Example:**
```bash
./3-k8s_db_secrets.sh -n obaas-dev -d cbankdb
./3-k8s_db_secrets.sh -n obaas-dev -d cbankdb -s my-custom-db-secret
```

**Secrets created:**

| Secret | Used By |
|--------|---------|
| `<dbname>-account-db-authn` | account, checks, testrunner |
| `<dbname>-customer-db-authn` | customer |
| `<dbname>-transfer-db-authn` | transfer |
| `<dbname>-creditscore-db-authn` | creditscore |

---

## Step 4: Deploy Services

**Time estimate:** ~5-10 minutes

**What this script does:**
- Validates prerequisites (kubectl, Helm, namespace, OBaaS release)
- Auto-detects OBaaS release name and container registry
- Verifies database secrets exist
- Verifies container images exist in registry
- Deploys all 6 services using the shared `obaas-sample-app` Helm chart
- Each service uses its own `values.yaml` file
- Uses `helm upgrade --install` with `--wait` flag
- The db-init job automatically creates database users on first deployment

**Command:**
```bash
./4-deploy_all_services.sh -n <namespace> -d <dbname> -p <prefix>
```

**Example:**
```bash
./4-deploy_all_services.sh -n obaas-dev -d cbankdb -p cloudbank-v5
```

**Monitor deployment:**
```bash
kubectl get pods -n <namespace> -w
```

**Expected:** All 6 pods show `1/1 Running` within 2-3 minutes.

---

## Step 5: Create APISIX Routes

**Time estimate:** ~1 minute

**What this script does:**
- Auto-detects OBaaS release name
- Retrieves APISIX admin key from the configmap
- Creates a port-forward to the APISIX admin service
- Creates routes for all CloudBank services using the APISIX Admin API
- Routes use Eureka service discovery
- Cleans up port-forward on completion

**Command:**
```bash
./5-apisix_create_routes.sh -n <namespace>
```

**Example:**
```bash
./5-apisix_create_routes.sh -n obaas-dev
```

**Routes created:**

| Route | URI Pattern | Service |
|-------|-------------|---------|
| 1000 | `/api/v1/account*` | ACCOUNT |
| 1001 | `/api/v1/creditscore*` | CREDITSCORE |
| 1002 | `/api/v1/customer*` | CUSTOMER |
| 1003 | `/api/v1/testrunner*` | TESTRUNNER |
| 1004 | `/api/v1/transfer*` | TRANSFER |

---

## Step 6: Verify Installation

### Get Gateway Address

```bash
kubectl get svc -n <namespace> | grep apisix-gateway
export IP=<EXTERNAL-IP>
```

For local testing without external IP:
```bash
kubectl port-forward -n <namespace> svc/apisix-gateway 8080:80 &
export IP=localhost:8080
```

### Test Services

```bash
# Account service
curl -s http://$IP/api/v1/account | jq

# Customer service
curl -s http://$IP/api/v1/customer | jq

# Credit score service
curl -s http://$IP/api/v1/creditscore | jq

# Transfer (account 2 → account 1)
curl -X POST "http://$IP/transfer?fromAccount=2&toAccount=1&amount=100"
```

### Check Eureka Registration

```bash
kubectl port-forward -n <namespace> svc/eureka 8761 &
# Open http://localhost:8761 - all 6 services should be registered
```

---

## Observability

### Eureka (Service Discovery)
```bash
kubectl port-forward -n <namespace> svc/eureka 8761
# http://localhost:8761
```

### Spring Boot Admin
```bash
kubectl port-forward -n <namespace> svc/admin-server 8989
# http://localhost:8989
```

### SigNoz (Tracing)
```bash
kubectl port-forward -n <namespace> svc/obaas-signoz-frontend 3301
# http://localhost:3301
# Credentials: kubectl get secret signoz-authn -n <namespace> -o jsonpath='{.data.email}' | base64 -d
```

### Service Logs
```bash
kubectl logs -n <namespace> -l app.kubernetes.io/name=account -f
```

---

## Troubleshooting

### Build Issues

| Problem | Solution |
|---------|----------|
| Maven dependency errors | Run `./2-images_build_push.sh` which handles dependencies automatically |
| Docker connection failed | Verify `DOCKER_HOST` is set and Docker is running |
| Registry push failed | Re-authenticate: `docker login <registry>` |

### Deployment Issues

| Problem | Solution |
|---------|----------|
| **ImagePullBackOff** | Verify images exist: `docker pull <image>`. Check repos are public. |
| **CrashLoopBackOff** | Check logs: `kubectl logs <pod> -n <namespace>`. Usually database connection issues. |
| **Pending (0/1)** | Wait 60-90s for Liquibase migrations. Check logs for errors. |

### Database Issues

| Problem | Solution |
|---------|----------|
| Connection refused | Verify secrets exist: `kubectl get secrets -n <namespace> \| grep db-authn` |
| User doesn't exist | Check db-init job: `kubectl logs job/<service>-db-init -n <namespace>` |
| Wrong password | Recreate secrets: `./3-k8s_db_secrets.sh -n <namespace> -d <dbname> --delete` |

### APISIX Issues

| Problem | Solution |
|---------|----------|
| Can't find configmap | Verify OBaaS release: `helm list -n <namespace>`. Use `-o <release>` flag. |
| Routes not working | Check Eureka registration. Verify gateway has external IP. |
| Plugin errors | Ensure OBaaS APISIX has opentelemetry plugin enabled. |

### Common Commands

```bash
# Check all pods
kubectl get pods -n <namespace>

# Describe failing pod
kubectl describe pod <pod> -n <namespace>

# Check pod logs
kubectl logs <pod> -n <namespace>

# Check previous crash logs
kubectl logs <pod> -n <namespace> --previous

# Check secrets
kubectl get secrets -n <namespace> | grep db-authn

# Check db-init job
kubectl get jobs -n <namespace> | grep db-init
kubectl logs job/<service>-db-init -n <namespace>
```

---

## Cleanup

### Uninstall Services
```bash
helm uninstall account customer transfer checks creditscore testrunner -n <namespace>
```

### Delete Secrets
```bash
kubectl delete secret <dbname>-account-db-authn <dbname>-customer-db-authn \
  <dbname>-transfer-db-authn <dbname>-creditscore-db-authn -n <namespace>
```

### Delete APISIX Routes
```bash
kubectl port-forward -n <namespace> svc/<obaas-release>-apisix-admin 9180 &
export APISIX_KEY=$(kubectl -n <namespace> get configmap <obaas-release>-apisix \
  -o jsonpath='{.data.config\.yaml}' | grep -A2 'name.*admin' | grep key | awk '{print $2}')
for id in 1000 1001 1002 1003 1004; do
  curl -X DELETE "http://localhost:9180/apisix/admin/routes/$id" -H "X-API-KEY: $APISIX_KEY"
done
```

### Delete OCI Repositories
```bash
./1-oci_repos.sh -c <compartment_name> -p <prefix> --delete
```

---

## Notes

- CloudBank must be installed in the **same namespace** as OBaaS
- CloudBank v5 has only been tested with Java 21
- All microservices use Spring Boot 3.4.6 with Spring Cloud 2024.0.1
- Database migrations for account and customer services are managed by Liquibase
- Distributed transactions use Oracle MicroTx LRA (Long Running Actions) pattern
- Event-driven workflows use Oracle Advanced Queuing (AQ) with JMS

---

## Additional Resources

- [CloudBank README](README.md) - Detailed testing guide
- [OBaaS Documentation](https://oracle.github.io/microservices-backend/obaas/)
- [Report Issues](https://github.com/oracle/microservices-backend/issues)
