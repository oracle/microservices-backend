# CloudBank v5 Deployment And Test Guide For AI Agents

This file directs an AI agent through deploying and testing `cloudbank-v5` in this repository.

CloudBank v5 is an application workload for Oracle Backend for Microservices and AI (OBaaS). This guide assumes OBaaS is already installed and healthy. Do not install, upgrade, or mutate the OBaaS platform from this guide. If OBaaS is missing or unhealthy, stop and ask the operator to provide a healthy OBaaS namespace and release before continuing.

## Source Rules

Use these local sources for CloudBank v5 deployment and testing truth:

- `cloudbank-v5/README.md`
- `cloudbank-v5/cloudbank-v5-install.md`
- `cloudbank-v5/cloudbank-test-doc.md`
- `cloudbank-v5/check_prereqs.sh`
- `cloudbank-v5/1-oci_repos.sh`
- `cloudbank-v5/2-images_build_push.sh`
- `cloudbank-v5/3-k8s_db_secrets.sh`
- `cloudbank-v5/4-deploy_all_services.sh`
- `cloudbank-v5/5-apisix_create_routes.sh`
- `cloudbank-v5/6-smoke_test_secure_services.sh`
- `cloudbank-v5/7-test_all_services.sh`
- `cloudbank-v5/*/values.yaml`
- `helm/app-charts/obaas-sample-app`
- `docs-source/site/docs/setup/helm`
- `helm/infra-charts`

Do not use older CloudBank documentation under `docs-source/cloudbank` for CloudBank v5. Do not infer CloudBank v5 behavior from earlier CloudBank versions or unrelated directories.

## Required Inputs

Before deployment, collect and record:

- `<namespace>`: Kubernetes namespace where OBaaS is already installed and where CloudBank v5 will be installed.
- `<obaas-release>`: Helm release name of the OBaaS platform in `<namespace>`.
- `<dbname>`: database name/prefix used by OBaaS and CloudBank secrets.
- `<priv-secret-name>`: optional privileged database secret name. Defaults to `<dbname>-db-priv-authn`; if custom, pass the same value with `-s` or `--priv-secret` to `check_prereqs.sh`, `3-k8s_db_secrets.sh`, and `4-deploy_all_services.sh`.
- `<compartment-name>`: OCI compartment name for OCIR repository creation.
- `<prefix>`: image repository prefix, usually `cloudbank-v5`.
- `<image-tag>`: image tag, default `0.0.1-SNAPSHOT`.
- `<registry>`: optional explicit registry path. If omitted, use OCI/OCIR auto-detection from the CloudBank scripts.
- `<repository-visibility>`: OCIR repository visibility, either public or private. The repository creation script defaults to public unless `--private` is supplied.
- `<image-pull-secret>`: optional Kubernetes pull secret for private or otherwise authenticated registries.
- `<gateway-url>`: optional APISIX gateway URL for smoke and all-services tests. If omitted, the test scripts create a local port-forward.
- `<owner-username>`: optional seeded customer/account owner username for full all-services tests. Defaults to `qwertysdwr`.
- `<owner-password>`: optional password used by `7-test_all_services.sh` when creating or resetting the owner user for authorization-code testing.

Default to OCI/OCIR image handling unless the operator provides an explicit registry. For non-OCI or explicitly provided registries, use `--registry`. Use `--image-pull-secret` only when the target cluster needs credentials to pull from the selected registry.

## Preflight

Run all commands from the repository root unless a step says to `cd cloudbank-v5`.

Confirm cluster access:

```bash
kubectl config current-context
kubectl get nodes
helm version
kubectl get ns
```

Confirm OBaaS is installed and healthy in the target namespace:

```bash
helm list -n <namespace>
kubectl get pods -n <namespace>
kubectl get svc -n <namespace>
kubectl get secret <priv-secret-name-or-dbname-db-priv-authn> -n <namespace>
kubectl get instrumentation traces-instrumentation -n <namespace>
```

Expected:

- `helm list -n <namespace>` includes `<obaas-release>`.
- OBaaS pods are running or otherwise healthy.
- `<priv-secret-name-or-dbname-db-priv-authn>` exists and contains the privileged database credential keys `username`, `password`, and `service`.
- `traces-instrumentation` exists when OBaaS observability and Java auto-instrumentation are enabled.

Run CloudBank prerequisite checks:

```bash
cd cloudbank-v5
./check_prereqs.sh --build
./check_prereqs.sh --deploy -n <namespace> -o <obaas-release> -d <dbname>
```

If the privileged secret has a custom name, include the same `-s` value:

```bash
cd cloudbank-v5
./check_prereqs.sh --deploy -n <namespace> -o <obaas-release> -d <dbname> -s <priv-secret-name>
```

If Java, Maven, Docker, Helm, `kubectl`, `jq`, OCI CLI, or registry access is missing, fix prerequisites before continuing.

CloudBank v5 has been tested with Java 21. `JAVA_HOME` must point to the Java 21 installation used by Maven.

## Deployment

CloudBank must be deployed into the same namespace as OBaaS. The seven deployed services are:

- `azn-server`
- `account`
- `customer`
- `creditscore`
- `transfer`
- `checks`
- `testrunner`

### 1. Create OCI Container Repositories

Use this step for the default OCI/OCIR path:

```bash
cd cloudbank-v5
./1-oci_repos.sh -c <compartment-name> -p <prefix>
```

Repository visibility is an operator choice. The script creates public repositories by default; use `--private` when the repositories must be private, or `--public` when you want the command to state the default explicitly. For review-only planning, use `--dry-run`.

For OCIR, repository display names must match the path after the tenancy namespace plus the service name. For example, if the explicit registry is:

```text
sjc.ocir.io/maacloud/andytael/cloudbank-v5
```

then the seven OCIR repository display names must be:

```text
andytael/cloudbank-v5/azn-server
andytael/cloudbank-v5/account
andytael/cloudbank-v5/customer
andytael/cloudbank-v5/creditscore
andytael/cloudbank-v5/transfer
andytael/cloudbank-v5/checks
andytael/cloudbank-v5/testrunner
```

### 2. Build And Push Images

For OCI/OCIR auto-detection:

```bash
cd cloudbank-v5
./2-images_build_push.sh -p <prefix> -t <image-tag> --yes
```

If the operator provides a non-OCI or explicit registry path:

```bash
cd cloudbank-v5
./2-images_build_push.sh -r <registry> -t <image-tag> --yes
```

For local development clusters where images are already available to the cluster runtime:

```bash
cd cloudbank-v5
./2-images_build_push.sh --skip-push --yes
```

Only use `--run-tests` when the operator wants Maven tests included in the image build. The default script behavior skips tests during the image build.

On slow networks, large image pushes can sit silent for several minutes. Do not interrupt a push only because there is no terminal output. If progress is unclear, check the OCI Console or use `oci artifacts container image list` before retrying; reruns can reuse already uploaded layers.

### 3. Create Database And Authorization Secrets

The privileged secret must already exist:

```bash
kubectl get secret <priv-secret-name-or-dbname-db-priv-authn> -n <namespace>
```

Create the CloudBank service database secrets, OAuth client secret, and persistent `azn-server` signing-key secret:

```bash
cd cloudbank-v5
./3-k8s_db_secrets.sh -n <namespace> -d <dbname>
```

If the privileged secret has a custom name:

```bash
cd cloudbank-v5
./3-k8s_db_secrets.sh -n <namespace> -d <dbname> -s <priv-secret-name>
```

Normal reruns preserve existing database-password secrets and the signing-key secret. Use `--delete` only when intentionally recreating demo auth secrets or rotating the signing key. Use `--rotate-db-passwords` only when intentionally changing the generated database user passwords. Do not print or commit generated secrets; use `--show-passwords` only on a private terminal when explicitly needed.

### 4. Deploy All CloudBank Services

For OCI/OCIR auto-detection:

```bash
cd cloudbank-v5
./4-deploy_all_services.sh \
  -n <namespace> \
  -o <obaas-release> \
  -d <dbname> \
  -p <prefix> \
  -t <image-tag> \
  --yes
```

For an explicit registry:

```bash
cd cloudbank-v5
./4-deploy_all_services.sh \
  -n <namespace> \
  -o <obaas-release> \
  -d <dbname> \
  -r <registry> \
  -t <image-tag> \
  --yes
```

For private or authenticated registries, include the pull secret. For public repositories that the cluster can pull anonymously, omit `--image-pull-secret`:

```bash
cd cloudbank-v5
./4-deploy_all_services.sh \
  -n <namespace> \
  -o <obaas-release> \
  -d <dbname> \
  -r <registry> \
  -t <image-tag> \
  --image-pull-secret <image-pull-secret> \
  --yes
```

If the privileged secret has a custom name, pass the same `-s` or `--priv-secret` value used with `3-k8s_db_secrets.sh`:

```bash
cd cloudbank-v5
./4-deploy_all_services.sh \
  -n <namespace> \
  -o <obaas-release> \
  -d <dbname> \
  -s <priv-secret-name> \
  -r <registry> \
  -t <image-tag> \
  --image-pull-secret <image-pull-secret> \
  --yes
```

The deploy script uses the local `helm/app-charts/obaas-sample-app` chart when available. It deploys `azn-server` first, then the protected resource-server services. It also injects database secret names, the privileged database secret name when `--priv-secret` is supplied, JWT validation settings, service-token settings, and the `azn-server` persistent signing-key volume.

If deployment fails because pods or db-init jobs are looking for `<dbname>-db-priv-authn` but OBaaS uses a different privileged secret name, rerun deployment with `-s <priv-secret-name>`. Do not create a compatibility alias secret unless the operator explicitly wants a temporary workaround.

Monitor rollout:

```bash
kubectl get pods -n <namespace> -w
```

Expected: all seven CloudBank service pods become `1/1 Running`. `azn-server` can take longer during database initialization and authorization-server startup.

### 5. Create APISIX Routes

Create public authorization-server routes and protected CloudBank API routes:

```bash
cd cloudbank-v5
./5-apisix_create_routes.sh -n <namespace> -o <obaas-release> -d <dbname>
```

The route script reads the APISIX admin key from `<obaas-release>-apisix`, reads the CloudBank OAuth client secret from `<dbname>-azn-server-auth`, port-forwards the APISIX admin service, and creates or updates the route set.

Routes include:

- public `/.well-known/*` and `/oauth2/*` routes to `AZN-SERVER`
- read routes for account, customer, and creditscore using `cloudbank.read`
- write/admin routes for account and customer using `cloudbank.write` or `cloudbank.admin`
- testrunner deposit route using `cloudbank.test`
- transfer route using `cloudbank.transfer`
- a deny-style external block for internal account journal routes

The `azn-server` user-management API `/user/api/v1*` must not be exposed through APISIX.

## Testing

Run the secured smoke test first. This is the quick route, OAuth, and basic workflow check:

```bash
cd cloudbank-v5
./6-smoke_test_secure_services.sh -n <namespace> -o <obaas-release> -d <dbname>
```

If the operator provides an external gateway URL:

```bash
cd cloudbank-v5
./6-smoke_test_secure_services.sh \
  -n <namespace> \
  -o <obaas-release> \
  -d <dbname> \
  --gateway-url <gateway-url>
```

Use read-only mode when mutating deposit and transfer checks are not acceptable:

```bash
cd cloudbank-v5
./6-smoke_test_secure_services.sh -n <namespace> -o <obaas-release> -d <dbname> --read-only
```

Expected smoke-test coverage:

- authorization metadata is reachable without a token
- JWKS is reachable and exposes a signing key id
- protected creditscore API returns `401` without a token
- protected creditscore API returns `200` with a read token
- `/user/api/v1*` is not externally routed
- internal account journal route is blocked through APISIX
- account IDs can be discovered
- testrunner deposit rejects a read token
- testrunner deposit accepts a test token, unless `--read-only` is used
- the transfer route rejects a non-owner client-credentials token with `403`, unless `--read-only` is used
- successful owner-scoped transfer workflow validation is performed by `7-test_all_services.sh`

Run the full all-services test after the smoke test. This is the authoritative end-to-end CloudBank validation:

```bash
cd cloudbank-v5
./7-test_all_services.sh -n <namespace> -o <obaas-release> -d <dbname>
```

If the operator provides an external gateway URL:

```bash
cd cloudbank-v5
./7-test_all_services.sh \
  -n <namespace> \
  -o <obaas-release> \
  -d <dbname> \
  --gateway-url <gateway-url>
```

If the default local ports conflict with existing port-forwards, override them:

```bash
cd cloudbank-v5
./7-test_all_services.sh \
  -n <namespace> \
  -o <obaas-release> \
  -d <dbname> \
  --local-port 19080 \
  --auth-local-port 19081 \
  --service-base-port 19100
```

Use read-only mode when mutating check deposit, check clear, and transfer checks are not acceptable:

```bash
cd cloudbank-v5
./7-test_all_services.sh -n <namespace> -o <obaas-release> -d <dbname> --read-only
```

If the seeded owner user must be customized, pass the owner values explicitly:

```bash
cd cloudbank-v5
./7-test_all_services.sh \
  -n <namespace> \
  -o <obaas-release> \
  -d <dbname> \
  --owner-username <owner-username> \
  --owner-password <owner-password>
```

Expected all-services coverage:

- all seven CloudBank Kubernetes deployments are available
- all seven direct `/actuator/health` checks return `UP`
- APISIX gateway, authorization metadata, JWKS, and scoped OAuth client tokens work
- the `azn-server` user-management API remains blocked through APISIX
- protected route `401` and wrong-scope `403` behavior is preserved
- owner-scoped account and customer APIs succeed with an authorization-code user token
- `testrunner` publishes a check deposit, `checks` creates and clears the account journal entry
- transfer completes through APISIX and updates source and target balances

Expected all-services result:

```text
PASS=<positive-number> FAIL=0
All CloudBank service tests passed
```

### Authorization Model For Tests

APISIX enforces route-level OAuth scopes, but CloudBank services also enforce service-side ownership. Client-credentials tokens such as `cloudbank-client` are valid for route and scope checks, but they are not a customer or account owner. Account detail, customer detail, journal reads, check workflow polling, and transfer verification must use a user token whose subject matches the target account/customer owner.

`7-test_all_services.sh` handles this by creating or resetting a seeded owner user through the internal `azn-server` API and minting an authorization-code plus PKCE token for that user. Do not weaken service authorization or APISIX routes to make tests pass.

For manual testing, follow `cloudbank-v5/cloudbank-test-doc.md`. Use `http://localhost` only with local port-forward testing. Use HTTPS for external gateway URLs so client secrets and tokens are not sent over plaintext network links.

## Verification Commands

Check deployed releases and pods:

```bash
helm list -n <namespace>
kubectl get pods -n <namespace>
kubectl get svc -n <namespace>
kubectl get jobs -n <namespace> | grep db-init
```

Check service logs:

```bash
kubectl logs -n <namespace> -l app.kubernetes.io/name=azn-server
kubectl logs -n <namespace> -l app.kubernetes.io/name=account
kubectl logs -n <namespace> -l app.kubernetes.io/name=customer
kubectl logs -n <namespace> -l app.kubernetes.io/name=creditscore
kubectl logs -n <namespace> -l app.kubernetes.io/name=transfer
kubectl logs -n <namespace> -l app.kubernetes.io/name=checks
kubectl logs -n <namespace> -l app.kubernetes.io/name=testrunner
```

Check OAuth endpoints through the APISIX gateway:

```bash
kubectl port-forward -n <namespace> svc/<obaas-release>-apisix-gateway 9080:80
curl -s http://127.0.0.1:9080/.well-known/oauth-authorization-server | jq
curl -s http://127.0.0.1:9080/oauth2/jwks | jq '.keys[].kid'
```

Run full automated verification:

```bash
cd cloudbank-v5
./7-test_all_services.sh -n <namespace> -o <obaas-release> -d <dbname>
```

Check Eureka registration:

```bash
kubectl port-forward -n <namespace> svc/<obaas-release>-eureka 8761:8761
```

Open `http://localhost:8761` and verify that the seven CloudBank services are registered.

Check Spring Boot Admin:

```bash
kubectl port-forward -n <namespace> svc/<obaas-release>-admin-server 8989:8989
```

Check SigNoz:

```bash
kubectl port-forward -n <namespace> svc/<obaas-release>-signoz 8080:8080
kubectl get secret signoz-authn -n <namespace> -o jsonpath='{.data.email}' | base64 -d
```

## Troubleshooting

### OBaaS Missing Or Unhealthy

Do not install OBaaS from this guide. Stop and ask the operator for a healthy OBaaS release in the target namespace. Useful read-only checks:

```bash
helm list -n <namespace>
kubectl get pods -n <namespace>
kubectl describe pod <pod> -n <namespace>
```

### Missing Privileged Database Secret

`3-k8s_db_secrets.sh` requires `<dbname>-db-priv-authn` or the custom secret passed with `-s`.

```bash
kubectl get secret <priv-secret-name-or-dbname-db-priv-authn> -n <namespace>
kubectl get secrets -n <namespace> | grep db-priv-authn
```

If it is missing, ask the operator to create or identify the privileged OBaaS database secret. If the secret exists but uses a custom name, use `-s <priv-secret-name>` with prerequisite checks, secret creation, and service deployment.

### ImagePullBackOff

Verify image path, tag, repository visibility, and pull secret when one is required:

```bash
kubectl describe pod <pod> -n <namespace>
docker manifest inspect <registry>/<service>:<image-tag>
kubectl get secret <image-pull-secret> -n <namespace>
```

For private or authenticated registries, rerun deployment with:

```bash
./4-deploy_all_services.sh -n <namespace> -o <obaas-release> -d <dbname> -r <registry> -t <image-tag> --image-pull-secret <image-pull-secret> --yes
```

If the environment uses a custom privileged secret, include `-s <priv-secret-name>` in the redeploy command.

### CrashLoopBackOff

Check current and previous logs:

```bash
kubectl logs <pod> -n <namespace>
kubectl logs <pod> -n <namespace> --previous
kubectl describe pod <pod> -n <namespace>
```

Common causes are database connection errors, missing auth secrets, failed Liquibase initialization, or unavailable `azn-server` token/JWKS endpoints.

If `checks` crashes with a duplicate Spring JMS bean definition, capture current and previous logs before changing anything:

```bash
kubectl logs -n <namespace> -l app.kubernetes.io/name=checks
kubectl logs -n <namespace> -l app.kubernetes.io/name=checks --previous
kubectl describe pod -n <namespace> -l app.kubernetes.io/name=checks
```

The known AQJMS compatibility failure signature includes:

- `checks` pod enters `CrashLoopBackOff`
- logs show duplicate bean `jmsListenerContainerFactoryConfigurer`
- logs reference both `org.springframework.boot.jms.autoconfigure.JmsAnnotationDrivenConfiguration` and `org.springframework.boot.autoconfigure.jms.JmsAnnotationDrivenConfiguration`

For this failure, downgrade the shared CloudBank AQJMS starter property in `cloudbank-v5/pom.xml`:

```xml
<oracle-springboot-aqjms-starter.version>26.0.1</oracle-springboot-aqjms-starter.version>
```

Then rebuild and push both `checks` and `testrunner` with the same registry and image tag selected for the run. `testrunner` must be rebuilt too because it uses the same parent AQJMS property. Redeploy both Helm releases with the same namespace, OBaaS release, database name, and privileged secret values selected during CloudBank deployment. Verify all seven CloudBank services are running, then run:

```bash
cd cloudbank-v5
./7-test_all_services.sh -n <namespace> -o <obaas-release> -d <dbname>
```

Save the original failure logs, rebuild output, redeploy output, final pod state, and full test output in the evidence directory.

### Database Initialization Failures

Check init jobs and database secrets:

```bash
kubectl get jobs -n <namespace> | grep db-init
kubectl logs job/<service>-db-init -n <namespace>
kubectl get secrets -n <namespace> | grep -E 'db-authn|azn-server'
```

Do not rotate passwords unless explicitly intended. If the demo passwords must be rotated:

```bash
cd cloudbank-v5
./3-k8s_db_secrets.sh -n <namespace> -d <dbname> --delete --rotate-db-passwords
./4-deploy_all_services.sh -n <namespace> -o <obaas-release> -d <dbname> -p <prefix> -t <image-tag> --yes
```

If the environment uses a custom privileged secret, include `-s <priv-secret-name>` in both commands.

This also rotates demo auth secrets and the signing key, so request new tokens after redeployment.

### APISIX Route Failures

Check OBaaS release name, APISIX admin config, and service discovery:

```bash
helm list -n <namespace>
kubectl get configmap <obaas-release>-apisix -n <namespace>
kubectl get svc -n <namespace> | grep apisix
kubectl get pods -n <namespace> | grep -E 'apisix|eureka|azn-server'
```

If services were redeployed or restarted, rerun:

```bash
cd cloudbank-v5
./5-apisix_create_routes.sh -n <namespace> -o <obaas-release> -d <dbname>
```

### Token Or Authorization Failures

Check `azn-server`, OAuth secrets, route scopes, and JWKS:

```bash
kubectl get secret <dbname>-azn-server-auth -n <namespace>
kubectl get secret <dbname>-azn-server-signing-key -n <namespace>
kubectl logs -n <namespace> -l app.kubernetes.io/name=azn-server
curl -s http://127.0.0.1:9080/oauth2/jwks | jq
```

Expected HTTP behavior:

- no bearer token on protected APIs: `401`
- wrong scope: `403`
- correct route scope: request passes APISIX and reaches the target service
- correct route scope plus matching owner token: success response for owner-scoped account, customer, journal, and transfer APIs

### Smoke Test Failures

Run read-only smoke tests to isolate auth and route issues from mutating workflow issues:

```bash
cd cloudbank-v5
./6-smoke_test_secure_services.sh -n <namespace> -o <obaas-release> -d <dbname> --read-only
```

If read-only succeeds but default smoke tests fail, inspect `account`, `testrunner`, `transfer`, database init jobs, and AQ/LRA-related logs.

Immediately after a redeploy, mutating smoke-test calls can occasionally time out while services finish Eureka registration and warm database connections. If token issuance, read-only checks, and expected `401` or `403` checks pass but a deposit or transfer call returns `504`, wait briefly and rerun the smoke test once before treating it as a persistent deployment failure.

### All-Services Test Failures

Run the full test when smoke tests pass but a complete workload validation is needed:

```bash
cd cloudbank-v5
./7-test_all_services.sh -n <namespace> -o <obaas-release> -d <dbname>
```

If `7-test_all_services.sh` returns `403` on account detail, customer detail, journal polling, or transfer, check that the owner user was created, the owner authorization-code token was issued, and the selected account/customer records are owned by that token subject. Use `--owner-username` and `--owner-password` only when the deployment uses different seeded data.

If account transactions return `204`, treat it as a valid empty-state response. The account service returns `204 No Content` when an accessible account has no matching transactions.

If the checks workflow fails after `testrunner deposit test` returns `201`, inspect `testrunner`, `checks`, Oracle AQ/JMS configuration, and account journal polling:

```bash
kubectl logs -n <namespace> -l app.kubernetes.io/name=testrunner
kubectl logs -n <namespace> -l app.kubernetes.io/name=checks
kubectl logs -n <namespace> -l app.kubernetes.io/name=account
```

## Cleanup

Only clean up when the operator explicitly asks for it.

Do not uninstall OBaaS as part of CloudBank cleanup. CloudBank cleanup removes only the sample workload, its APISIX routes, its Kubernetes secrets, its optional OCIR repositories, and the database users created for the sample.

CloudBank creates these database users:

- `USER_REPO`: used by `azn-server`
- `ACCOUNT`: used by `account`, `checks`, and `testrunner`
- `CUSTOMER`: used by `customer`
- `TRANSFER`: used by `transfer`
- `CREDITSCORE`: used by `creditscore`

### Delete APISIX Routes

Delete the CloudBank routes before uninstalling services so the gateway no longer sends traffic to services that are being removed:

```bash
kubectl port-forward -n <namespace> svc/<obaas-release>-apisix-admin 9180 &
export APISIX_KEY=$(kubectl -n <namespace> get configmap <obaas-release>-apisix \
  -o jsonpath='{.data.config\.yaml}' | grep -A2 'name.*admin' | grep key | awk '{print $2}')
for id in 999 1000 1001 1002 1003 1004 1005 1006 1007 1008 1010 1011 1012; do
  curl --noproxy '*' -X DELETE "http://localhost:9180/apisix/admin/routes/$id" -H "X-API-KEY: $APISIX_KEY"
done
```

### Uninstall CloudBank Services

```bash
helm uninstall azn-server account customer creditscore transfer checks testrunner -n <namespace>
```

Verify the releases are gone:

```bash
helm list -n <namespace> | grep -E 'azn-server|account|customer|creditscore|transfer|checks|testrunner'
kubectl get pods -n <namespace> | grep -E 'azn-server|account|customer|creditscore|transfer|checks|testrunner'
```

### Drop CloudBank Database Users And Liquibase Tables

Run database cleanup only when the operator confirms that CloudBank sample data can be destroyed. Use the same privileged secret selected during install. If a custom secret was used, use that value for `<priv-secret-name>`; otherwise use `<dbname>-db-priv-authn`.

The `DROP USER ... CASCADE` commands remove each CloudBank user's objects, including application tables and any Liquibase metadata tables in those user schemas. The final block also removes CloudBank changelog rows from the privileged schema and drops the privileged schema's `DATABASECHANGELOG` and `DATABASECHANGELOGLOCK` tables only if they are empty afterward.

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

Do not drop the OBaaS platform database user or privileged database secret as part of CloudBank cleanup.

### Delete CloudBank Secrets

Delete CloudBank secrets only when the operator confirms secret removal. This removes the sample app DB credentials and `azn-server` demo auth material, but it does not remove the privileged OBaaS DB secret:

```bash
kubectl delete secret \
  <dbname>-azn-server-db-authn \
  <dbname>-azn-server-auth \
  <dbname>-azn-server-signing-key \
  <dbname>-account-db-authn \
  <dbname>-customer-db-authn \
  <dbname>-transfer-db-authn \
  <dbname>-creditscore-db-authn \
  -n <namespace>
```

If a temporary compatibility privileged-secret alias was created during troubleshooting, such as `<dbname>-db-priv-authn` pointing at the real OBaaS privileged secret, delete that alias after CloudBank DB cleanup succeeds:

```bash
kubectl delete secret <dbname>-db-priv-authn -n <namespace>
```

Do not delete shared image pull secrets such as `ocir-auth` unless the operator confirms they are not referenced by OBaaS or other workloads. Before removing a pull secret, check live workloads:

```bash
kubectl get deploy,sts,ds,pod -n <namespace> -o yaml | grep -A2 imagePullSecrets
```

### Verify No CloudBank Leftovers

Verify that only OBaaS remains and that CloudBank resources, routes, database users, and Liquibase tables are gone:

```bash
helm list -n <namespace>
kubectl get all,secret,configmap,pvc,job,ingress -n <namespace> \
  | grep -E 'cloudbank|<dbname>|azn-server|account|customer|transfer|creditscore|checks|testrunner'
```

The resource grep should return no CloudBank matches. APISIX route IDs `999` through `1008`, `1010`, `1011`, and `1012` should return `404` from the APISIX Admin API. A privileged DB verification query should show:

```text
CLOUDBANK_USER_COUNT = 0
LIQUIBASE_TABLE_COUNT = 0
```

### Delete OCI Repositories

Delete OCI repositories only when the operator confirms repository removal. The repositories may be public or private; deletion removes the repository and stored images either way:

```bash
cd cloudbank-v5
./1-oci_repos.sh -c <compartment-name> -p <prefix> --delete
```
