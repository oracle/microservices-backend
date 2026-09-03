# CloudBank v5 Installation Guide

## Overview

CloudBank v5 is a reference application demonstrating cloud-native microservices architecture using Oracle Backend as a Service (OBaaS). It consists of seven interconnected Spring services:

| Service | Purpose |
|---------|---------|
| **account** | Manages accounts, balances, and transactions (LRA participant) |
| **customer** | Handles customer profiles (Oracle ADB 23ai) |
| **transfer** | Orchestrates money transfers (LRA coordinator, Saga pattern) |
| **checks** | Processes check deposits asynchronously (Oracle AQ, JMS) |
| **creditscore** | Provides credit scoring (stateless REST) |
| **testrunner** | Test harness for workflows (AQ producer) |
| **azn-server** | Spring Authorization Server for CloudBank OAuth2/JWT tokens |

**Technology Stack:** Spring Boot 3.5, Spring Security, Spring Authorization Server, Oracle Database, MicroTx, Oracle AQ, OBaaS Java auto-instrumentation

---

## Overview of Installation

The installation process consists of five install steps plus verification:

| Step | Script | Description |
|------|--------|-------------|
| 1 | `1-oci_repos.sh` | Create container repositories in OCI Registry |
| 2 | `2-images_build_push.sh` | Build and push microservice container images |
| 3 | `3-k8s_db_secrets.sh` | Create Kubernetes secrets for database credentials, OAuth client credentials, and signing keys |
| 4 | `4-deploy_all_services.sh` | Deploy all services using Helm |
| 5 | `5-apisix_create_routes.sh` | Create secured APISIX API Gateway routes |

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
- **jq** for the verification commands
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

CloudBank must be installed in the **same namespace** as OBaaS. Services require access to OBaaS components (Eureka, APISIX, database secrets, and the OBaaS OpenTelemetry instrumentation resource) within the same namespace.

OBaaS 2.1.0-build.12 uses Java agent auto-injection for CloudBank telemetry. The CloudBank services enable this through their `values.yaml` files; tracing/exporter dependencies are not packaged into the applications.

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
# For automation:
./2-images_build_push.sh -p <prefix> --yes

# Step 3: Create database and authorization secrets (can run while Step 2 is building)
./3-k8s_db_secrets.sh -n <namespace> -d <dbname>

# Step 4: Deploy services
./4-deploy_all_services.sh -n <namespace> -d <dbname> -p <prefix>
# For automation:
./4-deploy_all_services.sh -n <namespace> -d <dbname> -p <prefix> --yes

# Step 5: Create APISIX routes
./5-apisix_create_routes.sh -n <namespace> -d <dbname>

# Step 6: Run secured service smoke tests
./6-smoke_test_secure_services.sh -n <namespace> -d <dbname>

# Verify pods directly if needed
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
- Creates 7 container repositories (azn-server, account, customer, transfer, checks, creditscore, testrunner)
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
- Builds all 7 service JARs using Maven
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
Use `--yes` for non-interactive automation.

---

## Step 3: Create Database And Authorization Secrets

**Time estimate:** ~1 minute

**What this script does:**
- Validates the privileged secret `<dbname>-db-priv-authn` exists
- Reads the TNS service name from the privileged secret
- Generates Oracle-compatible passwords for each service account
- Creates Kubernetes secrets with username, password, and service keys
- Usernames are uppercase (Oracle requirement)
- Creates the azn-server bootstrap and scoped OAuth client secrets used by secured services, tests, and APISIX
- Creates the azn-server persistent OAuth signing-key secret
- Hides generated plaintext passwords by default; use `--show-passwords` only on a private terminal

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
# Optional unsafe display of generated values:
./3-k8s_db_secrets.sh -n <namespace> -d <dbname> --show-passwords
```

**Example:**
```bash
./3-k8s_db_secrets.sh -n obaas-dev -d cbankdb
./3-k8s_db_secrets.sh -n obaas-dev -d cbankdb -s my-custom-db-secret
```

**Secrets created:**

| Secret | Used By |
|--------|---------|
| `<dbname>-azn-server-db-authn` | azn-server database user |
| `<dbname>-azn-server-auth` | azn-server bootstrap users, scoped OAuth clients, APISIX OIDC client |
| `<dbname>-azn-server-signing-key` | azn-server persistent OAuth token signing key |
| `<dbname>-account-db-authn` | account, checks, testrunner |
| `<dbname>-customer-db-authn` | customer |
| `<dbname>-transfer-db-authn` | transfer |
| `<dbname>-creditscore-db-authn` | creditscore |

Rerunning the script preserves existing database-password secrets and the existing signing-key secret. With `--delete`, database auth secrets are recreated but existing database usernames/passwords are reused unless `--rotate-db-passwords` is also supplied. Use `--delete` only when you intentionally want to rotate the demo auth secrets and signing key; existing access tokens become invalid after signing-key rotation.

If you are upgrading an existing secure CloudBank demo that already has `<dbname>-azn-server-auth`, rerun step 3 with `--delete` so the secret includes the scoped client keys `service-client-secret`, `test-client-secret`, and `admin-client-secret`.

---

## Step 4: Deploy Services

**Time estimate:** ~5-10 minutes

**What this script does:**
- Validates prerequisites (kubectl, Helm, namespace, OBaaS release)
- Auto-detects OBaaS release name and container registry
- Verifies the privileged database secret and application database secrets exist
- Verifies container images exist in registry
- Deploys all 7 services using the shared `obaas-sample-app` Helm chart
- Deploys `azn-server` before the protected resource-server services
- Passes JWT resource-server and service-token settings to the protected services
- Mounts `<dbname>-azn-server-signing-key` into `azn-server` so issued tokens remain verifiable across pod restarts
- Each service uses its own `values.yaml` file
- Uses `helm upgrade --install` with `--wait` flag
- The db-init job automatically creates database users on first deployment

**Command:**
```bash
./4-deploy_all_services.sh -n <namespace> -d <dbname> -p <prefix>
# Or with a custom privileged secret name:
./4-deploy_all_services.sh -n <namespace> -d <dbname> -s <secret-name> -p <prefix>
```

**Example:**
```bash
./4-deploy_all_services.sh -n obaas-dev -d cbankdb -p cloudbank-v5
./4-deploy_all_services.sh -n obaas-dev -d cbankdb -s my-custom-db-secret -p cloudbank-v5
```

**Monitor deployment:**
```bash
kubectl get pods -n <namespace> -w
```

**Expected:** All 7 pods show `1/1 Running` within 5-10 minutes. `azn-server` can take longer than the other services during Liquibase and authorization-server startup.

---

## Step 5: Create APISIX Routes

**Time estimate:** ~1 minute

**What this script does:**
- Auto-detects OBaaS release name
- Retrieves APISIX admin key from the configmap
- Reads the normal API OAuth client secret from `<dbname>-azn-server-auth`
- Creates a port-forward to the APISIX admin service
- Creates public authorization-server routes and protected CloudBank API routes using the APISIX Admin API
- Adds APISIX `openid-connect` bearer-token validation to protected routes and forwards the access token to backend services
- Routes use Eureka service discovery
- Cleans up port-forward on completion

**Command:**
```bash
./5-apisix_create_routes.sh -n <namespace> -d <dbname>
```

**Example:**
```bash
./5-apisix_create_routes.sh -n obaas-dev -d cbankdb
```

**Routes created:**

| Route | Methods | URI Pattern | Service | APISIX Scope |
|-------|---------|-------------|---------|--------------|
| 999 | All | `/api/v1/account/journal*` | ACCOUNT | `cloudbank.external-denied` |
| 1000 | GET, HEAD | `/api/v1/account*` | ACCOUNT | `cloudbank.read` |
| 1001 | GET, HEAD | `/api/v1/creditscore*` | CREDITSCORE | `cloudbank.read` |
| 1002 | GET, HEAD | `/api/v1/customer*` | CUSTOMER | `cloudbank.read` |
| 1003 | POST | `/api/v1/testrunner*` | TESTRUNNER | `cloudbank.test` |
| 1004 | POST | `/transfer` | TRANSFER | `cloudbank.transfer` |
| 1005 | POST | `/api/v1/account` | ACCOUNT | `cloudbank.write` |
| 1006 | DELETE | `/api/v1/account*` | ACCOUNT | `cloudbank.admin` |
| 1007 | POST, PUT | `/api/v1/customer*` | CUSTOMER | `cloudbank.write` |
| 1008 | DELETE | `/api/v1/customer*` | CUSTOMER | `cloudbank.admin` |
| 1010 | All | `/.well-known/*` | AZN-SERVER | Public |
| 1011 | All | `/oauth2/*` | AZN-SERVER | Public |

The `azn-server` user-management API (`/user/api/v1*`) is intentionally not routed through APISIX. It is for cluster-internal or administrative access only.

---

## Step 6: Verify Installation

### Automated Smoke Test

Run the secured smoke-test script first. It verifies public authorization metadata/JWKs, token issuance, protected-route authentication, scope-based authorization, account lookup, check deposit, and that the transfer route rejects a non-owner client-credentials token through APISIX. Successful owner-scoped transfer workflow validation is performed by `7-test_all_services.sh`.

```bash
./6-smoke_test_secure_services.sh -n <namespace> -d <dbname>
```

Use `--read-only` to skip the mutating deposit and transfer checks.

### Get Gateway Address

```bash
kubectl get svc -n <namespace> | grep apisix-gateway
export IP=<EXTERNAL-IP>
```

For local testing without external IP:
```bash
kubectl port-forward -n <namespace> svc/<obaas-release>-apisix-gateway 8080:80 &
export IP=localhost:8080
```

### Get Access Tokens

Protected CloudBank APIs require bearer tokens. `3-k8s_db_secrets.sh` creates scoped sample clients. Use `http://localhost` only with a local port-forward; use HTTPS for any external gateway URL so client secrets and tokens are not sent over plaintext network links.

```bash
export CLIENT_ID=cloudbank-client
export CLIENT_SECRET=$(kubectl get secret <dbname>-azn-server-auth -n <namespace> \
  -o jsonpath='{.data.client-secret}' | base64 -d)
export TEST_CLIENT_ID=cloudbank-test-client
export TEST_CLIENT_SECRET=$(kubectl get secret <dbname>-azn-server-auth -n <namespace> \
  -o jsonpath='{.data.test-client-secret}' | base64 -d)

export READ_TOKEN=$(curl -s -u "$CLIENT_ID:$CLIENT_SECRET" \
  -X POST "http://$IP/oauth2/token" \
  -d grant_type=client_credentials \
  -d scope=cloudbank.read | jq -r .access_token)

export TEST_TOKEN=$(curl -s -u "$TEST_CLIENT_ID:$TEST_CLIENT_SECRET" \
  -X POST "http://$IP/oauth2/token" \
  -d grant_type=client_credentials \
  -d scope=cloudbank.test | jq -r .access_token)

export TRANSFER_TOKEN=$(curl -s -u "$CLIENT_ID:$CLIENT_SECRET" \
  -X POST "http://$IP/oauth2/token" \
  -d grant_type=client_credentials \
  -d scope=cloudbank.transfer | jq -r .access_token)
```

### Test Services

```bash
# Public authorization-server metadata
curl -s http://$IP/.well-known/oauth-authorization-server | jq

# Account service. Pick valid IDs from this list for deposit/transfer tests.
curl -s -H "Authorization: Bearer $READ_TOKEN" http://$IP/api/v1/accounts | jq
FROM_ACCOUNT_ID=<account-id-with-positive-balance>
TO_ACCOUNT_ID=<another-account-id>

# Customer service
curl -s -H "Authorization: Bearer $READ_TOKEN" http://$IP/api/v1/customer | jq

# Credit score service
curl -s -H "Authorization: Bearer $READ_TOKEN" http://$IP/api/v1/creditscore | jq

# Test runner AQ workflow
curl -s -X POST -H "Authorization: Bearer $TEST_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"accountId\":${TO_ACCOUNT_ID},\"amount\":1}" \
  http://$IP/api/v1/testrunner/deposit | jq

# Transfer
curl -s -X POST -H "Authorization: Bearer $TRANSFER_TOKEN" \
  "http://$IP/transfer?fromAccount=${FROM_ACCOUNT_ID}&toAccount=${TO_ACCOUNT_ID}&amount=1"
```

### Check Eureka Registration

```bash
kubectl port-forward -n <namespace> svc/eureka 8761 &
# Open http://localhost:8761 - all 7 services should be registered
```

---

## Observability

CloudBank uses the OBaaS Java instrumentation auto-injection model. The service Helm values set `otel.enabled: true`, which causes OBaaS to inject the Java agent with the namespace `traces-instrumentation` resource. Tune Java agent settings in OBaaS values, not in CloudBank application POMs.

### Eureka (Service Discovery)
```bash
kubectl port-forward -n <namespace> svc/eureka 8761
# http://localhost:8761
```

### Spring Boot Admin
```bash
kubectl port-forward -n <namespace> svc/<obaas-release>-admin-server 8989
# http://localhost:8989
```

### SigNoz (Tracing)
```bash
kubectl port-forward -n <namespace> svc/<obaas-release>-signoz 8080
# http://localhost:8080
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
| Wrong password | First verify the database user password matches the Kubernetes secret. If you intentionally need new demo database passwords, recreate secrets with `./3-k8s_db_secrets.sh -n <namespace> -d <dbname> --delete --rotate-db-passwords`, then redeploy. This also rotates demo auth secrets and the signing key, so request fresh tokens afterwards. |

### APISIX Issues

| Problem | Solution |
|---------|----------|
| Can't find configmap | Verify OBaaS release: `helm list -n <namespace>`. Use `-o <release>` flag. |
| Routes not working | Check Eureka registration and verify the gateway has an external IP. If services were just redeployed or restarted, rerun `./5-apisix_create_routes.sh` to refresh APISIX route/discovery state. |
| Plugin errors | Ensure OBaaS APISIX has `opentelemetry`, `prometheus`, and `openid-connect` plugins enabled. |
| Protected APIs return `401` | Get a token from `/oauth2/token` and pass `Authorization: Bearer <token>`. |
| Protected APIs return `403` | Request the scope required by the route, such as `cloudbank.read`, `cloudbank.test`, or `cloudbank.transfer`. |
| Token requests fail | Verify `<dbname>-azn-server-auth` exists and that `azn-server` is running. |
| Tokens fail after `azn-server` restart | Verify `<dbname>-azn-server-signing-key` exists and was not rotated with `--delete`. |

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
kubectl get secrets -n <namespace> | grep -E 'db-authn|azn-server'

# Check db-init job
kubectl get jobs -n <namespace> | grep db-init
kubectl logs job/<service>-db-init -n <namespace>
```

---

## Cleanup

Only run cleanup when the CloudBank sample workload and sample data can be removed. Do not uninstall OBaaS as part of CloudBank cleanup.

### Delete APISIX Routes

Delete CloudBank routes first so APISIX no longer routes traffic to services that are being removed:

```bash
kubectl port-forward -n <namespace> svc/<obaas-release>-apisix-admin 9180 &
export APISIX_KEY=$(kubectl -n <namespace> get configmap <obaas-release>-apisix \
  -o jsonpath='{.data.config\.yaml}' | grep -A2 'name.*admin' | grep key | awk '{print $2}')
for id in 999 1000 1001 1002 1003 1004 1005 1006 1007 1008 1010 1011 1012; do
  curl --noproxy '*' -X DELETE "http://localhost:9180/apisix/admin/routes/$id" -H "X-API-KEY: $APISIX_KEY"
done
```

### Uninstall Services

```bash
helm uninstall azn-server account customer transfer checks creditscore testrunner -n <namespace>
```

Verify the releases and pods are gone:

```bash
helm list -n <namespace> | grep -E 'azn-server|account|customer|creditscore|transfer|checks|testrunner'
kubectl get pods -n <namespace> | grep -E 'azn-server|account|customer|creditscore|transfer|checks|testrunner'
```

### Drop Database Users And Liquibase Tables

CloudBank creates these database users:

| User | Used by |
| --- | --- |
| `USER_REPO` | `azn-server` |
| `ACCOUNT` | `account`, `checks`, `testrunner` |
| `CUSTOMER` | `customer` |
| `TRANSFER` | `transfer` |
| `CREDITSCORE` | `creditscore` |

Run database cleanup only when the CloudBank sample data can be destroyed. Use the same privileged secret used during deployment. If you deployed with `-s <priv-secret-name>` or `--priv-secret <priv-secret-name>`, use that secret below. Otherwise use `<dbname>-db-priv-authn`.

`DROP USER ... CASCADE` removes each CloudBank user's objects, including application tables and Liquibase metadata tables in those user schemas. The final block removes CloudBank changelog rows from the privileged schema and drops the privileged schema's `DATABASECHANGELOG` and `DATABASECHANGELOGLOCK` tables only if they are empty afterward.

For ADB wallet-backed environments, replace `<wallet-secret-name>` with the active OBaaS wallet secret, for example `<obaas-release>-adb-tns-admin-<revision>`. If the database does not require a wallet, remove `TNS_ADMIN`, the `volumeMounts`, and the `volumes` block.

```bash
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: cloudbank-db-cleanup
  namespace: <namespace>
spec:
  restartPolicy: Never
  containers:
  - name: cloudbank-db-cleanup
    image: container-registry.oracle.com/database/sqlcl:26.2.2
    command: ["/bin/sh", "-c"]
    args:
    - |
      cat >/tmp/cloudbank-db-cleanup.sql <<SQL
      connect "$PRIV_USERNAME"/"$PRIV_PASSWORD"@$PRIV_SERVICE
      WHENEVER SQLERROR EXIT SQL.SQLCODE
      WHENEVER OSERROR EXIT 1

      DECLARE
        l_changelog_exists NUMBER;
        l_changelog_rows   NUMBER := 0;

        PROCEDURE drop_user_if_exists(p_username IN VARCHAR2) IS
          l_count NUMBER;
        BEGIN
          SELECT COUNT(*) INTO l_count FROM dba_users WHERE username = UPPER(p_username);
          IF l_count > 0 THEN
            EXECUTE IMMEDIATE 'DROP USER "' || UPPER(p_username) || '" CASCADE';
          END IF;
        END;

        PROCEDURE drop_table_if_exists(p_table_name IN VARCHAR2) IS
          l_exists NUMBER;
        BEGIN
          SELECT COUNT(*) INTO l_exists FROM user_tables WHERE table_name = UPPER(p_table_name);
          IF l_exists > 0 THEN
            EXECUTE IMMEDIATE 'DROP TABLE "' || UPPER(p_table_name) || '" PURGE';
          END IF;
        END;
      BEGIN
        drop_user_if_exists('USER_REPO');
        drop_user_if_exists('ACCOUNT');
        drop_user_if_exists('CUSTOMER');
        drop_user_if_exists('TRANSFER');
        drop_user_if_exists('CREDITSCORE');

        SELECT COUNT(*) INTO l_changelog_exists FROM user_tables WHERE table_name = 'DATABASECHANGELOG';
        IF l_changelog_exists > 0 THEN
          EXECUTE IMMEDIATE q'[DELETE FROM "DATABASECHANGELOG" WHERE author IN ('az_admin', 'account', 'customer')]';
          EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM "DATABASECHANGELOG"' INTO l_changelog_rows;
        END IF;

        IF l_changelog_rows = 0 THEN
          drop_table_if_exists('DATABASECHANGELOG');
          drop_table_if_exists('DATABASECHANGELOGLOCK');
        END IF;

        COMMIT;
      END;
      /
      SQL
      sql /nolog @/tmp/cloudbank-db-cleanup.sql
    env:
    - name: TNS_ADMIN
      value: /app/tns_admin
    - name: PRIV_USERNAME
      valueFrom:
        secretKeyRef:
          name: <priv-secret-name>
          key: username
    - name: PRIV_PASSWORD
      valueFrom:
        secretKeyRef:
          name: <priv-secret-name>
          key: password
    - name: PRIV_SERVICE
      valueFrom:
        secretKeyRef:
          name: <priv-secret-name>
          key: service
    volumeMounts:
    - name: tns-admin
      mountPath: /app/tns_admin
      readOnly: true
  volumes:
  - name: tns-admin
    secret:
      secretName: <wallet-secret-name>
YAML

kubectl wait -n <namespace> --for=jsonpath='{.status.phase}'=Succeeded pod/cloudbank-db-cleanup --timeout=10m
kubectl logs -n <namespace> pod/cloudbank-db-cleanup
kubectl delete pod -n <namespace> cloudbank-db-cleanup
```

Do not drop the OBaaS platform database user, the OBaaS namespace, the OBaaS Helm release, or the privileged database secret as part of CloudBank cleanup.

### Delete Secrets

Delete CloudBank secrets only after DB cleanup succeeds and only when secret removal is intended:

```bash
kubectl delete secret <dbname>-azn-server-db-authn <dbname>-azn-server-auth \
  <dbname>-azn-server-signing-key \
  <dbname>-account-db-authn <dbname>-customer-db-authn \
  <dbname>-transfer-db-authn <dbname>-creditscore-db-authn -n <namespace>
```

### Delete OCI Repositories

Repository deletion is optional and removes stored images whether the repositories were public or private:

```bash
./1-oci_repos.sh -c <compartment_name> -p <prefix> --delete
```

---

## Notes

- CloudBank must be installed in the **same namespace** as OBaaS
- CloudBank v5 has only been tested with Java 21
- All Spring services use Spring Boot 3.5.x with Spring Cloud 2025.x
- Secured APIs validate JWTs from `azn-server`; APISIX also validates and forwards bearer tokens for externally routed CloudBank APIs
- OBaaS 2.1.0-build.12 supplies Java telemetry through auto-injected instrumentation
- Database migrations for account and customer services are managed by Liquibase
- Distributed transactions use Oracle MicroTx LRA (Long Running Actions) pattern
- Event-driven workflows use Oracle Advanced Queuing (AQ) with JMS

---

## Additional Resources

- [CloudBank README](README.md) - Project overview
- [CloudBank Testing Guide](cloudbank-test-doc.md) - Detailed testing guide
- [OBaaS Documentation](https://oracle.github.io/microservices-backend/obaas/)
- [Report Issues](https://github.com/oracle/microservices-backend/issues)
