---
title: Oracle Database Operator for Kubernetes
sidebar_position: 6
---

The Oracle Database Operator for Kubernetes (_OraOperator_, or simply the _operator_) extends the Kubernetes API with custom resources and controllers to automate Oracle Database lifecycle management.

[Full Documentation](https://github.com/oracle/oracle-database-operator).

Learn about using the OraOperator in the Livelab [Microservices and Kubernetes for an Oracle DBA](https://apexapps.oracle.com/pls/apex/dbpm/r/livelabs/view-workshop?wid=3734)

## Installing the Oracle Database Operator for Kubernetes

Oracle Database Operator for Kubernetes will be installed if the `oracle-database-operator.enabled` is set to `true` in the `values.yaml` file. The default namespace for Oracle Database Operator is `oracle-database-operator-system`.

## Deploy ORDS with the Oracle Database Operator

Use the `OrdsSrvs` custom resource to deploy Oracle REST Data Services (ORDS) into an OBaaS namespace.

### Prerequisites

Before you create the ORDS resource, confirm that:

- Oracle Database Operator is installed.
- The `ordssrvs.database.oracle.com` custom resource exists.
- The OBaaS namespace exists.
- The database administrator Secret exists.
- The database connection details are known.

```bash
kubectl get crd ordssrvs.database.oracle.com
kubectl get secret <db-admin-secret> -n <application-namespace>
```

Create a Secret for the ORDS runtime database user password:

```bash
read -r -s ORDS_RUNTIME_PASSWORD
printf '%s' "${ORDS_RUNTIME_PASSWORD}" | kubectl -n <application-namespace> create secret generic <ords-runtime-secret> \
  --from-file=password=/dev/stdin
unset ORDS_RUNTIME_PASSWORD
```

### Database connection settings

Use the connection settings that match the OBaaS database type.

| OBaaS database type | ORDS connection type | Required connection details |
| --- | --- | --- |
| `ADB-S` | `tns` | ADB wallet Secret and TNS alias |
| `SIDB-FREE` | `basic` | In-cluster database service, port `1521`, service `FREEPDB1` |
| `OTHER` | `basic` or `customurl` | External host, port, service name, or JDBC URL |

### Create the ORDS resource

Create a file named `ords.yaml`.

```yaml
apiVersion: database.oracle.com/v4
kind: OrdsSrvs
metadata:
  name: <ords-resource-name>
  namespace: <application-namespace>
spec:
  image: container-registry.oracle.com/database/ords:25.1.0
  imagePullPolicy: IfNotPresent
  workloadType: Deployment
  replicas: 1
  globalSettings:
    standalone.context.path: /ords
    standalone.http.port: 8080
    standalone.https.port: 8443
    security.forceHTTPS: true
    database.api.enabled: true
  poolSettings:
    - poolName: <pool-name>

      # Add the database connection settings for ADB-S, SIDB-FREE, or OTHER here.

      db.username: ORDS_PUBLIC_USER_OPER
      db.secret:
        secretName: <ords-runtime-secret>
        passwordKey: password
      db.adminUser: <ADMIN-or-SYSTEM>
      db.adminUser.secret:
        secretName: <db-admin-secret>
        passwordKey: password

      restEnabledSql.active: true
      feature.sdw: true
      plsql.gateway.mode: proxied
      jdbc.InitialLimit: 2
      jdbc.MinLimit: 2
      jdbc.MaxLimit: 10
```

For `ADB-S`, add:

```yaml
      db.connectionType: tns
      db.tnsAliasName: <tns-alias>
      tnsAdminSecret:
        secretName: <adb-wallet-secret>
```

For `SIDB-FREE`, add:

```yaml
      db.connectionType: basic
      db.hostname: <db-service-name>
      db.port: 1521
      db.servicename: FREEPDB1
```

You can find the in-cluster database service with:

```bash
kubectl get svc -n <application-namespace> -l app.kubernetes.io/component=database
```

For `OTHER`, add:

```yaml
      db.connectionType: basic
      db.hostname: <db-host>
      db.port: <db-port>
      db.servicename: <db-service-name>
```

If the database requires a JDBC URL, use:

```yaml
      db.connectionType: customurl
      db.customURL: <jdbc-url>
```

### Apply and verify

Validate the resource before applying it:

```bash
kubectl apply --dry-run=server -f ords.yaml
kubectl apply -f ords.yaml
```

Check the ORDS resource, pods, and service:

```bash
kubectl get ordssrvs <ords-resource-name> -n <application-namespace>
kubectl get pods,svc -n <application-namespace> -l app=<ords-resource-name>
```

Test the ORDS endpoint locally:

```bash
kubectl -n <application-namespace> port-forward service/<ords-resource-name> 18443:8443
curl -k -i https://localhost:18443/ords/<pool-name>/_/db-api/stable/
```

### Optional: Route ORDS through APISIX

You can keep ORDS internal and access it with `kubectl port-forward`, as shown above. Only create an APISIX route when you want ORDS reachable through the OBaaS APISIX gateway.

If your APISIX gateway is exposed outside the cluster, this route can make ORDS reachable from that same network path. Review your gateway, hostname, TLS, and access-control configuration before using this option in a shared or production environment.

The examples below use these service name patterns:

| Service | Name |
| --- | --- |
| APISIX admin API | `<app-release>-apisix-admin` |
| APISIX gateway | `<app-release>-apisix-gateway` |
| ORDS | `<ords-resource-name>` |
| SigNoz OpenTelemetry collector alias | `signoz-otel-collector` |

Confirm the services exist:

```bash
kubectl get svc -n <application-namespace> \
  <app-release>-apisix-admin \
  <app-release>-apisix-gateway \
  <ords-resource-name> \
  signoz-otel-collector
```

Confirm that APISIX has the OpenTelemetry plugin enabled:

```bash
kubectl -n <application-namespace> get configmap <app-release>-apisix -o yaml \
  | yq '.data."config.yaml"' \
  | yq '.plugins[]' \
  | grep opentelemetry
```

Open a local tunnel to the APISIX admin API:

```bash
kubectl -n <application-namespace> port-forward service/<app-release>-apisix-admin 9180:9180
```

In another terminal, retrieve the APISIX admin key:

```bash
admin_key=$(
  kubectl -n <application-namespace> get configmap <app-release>-apisix -o yaml \
    | yq '.data."config.yaml"' \
    | yq '.deployment.admin.admin_key[] | select(.name == "admin") | .key'
)
```

APISIX OpenTelemetry plugin metadata (`plugin_metadata/opentelemetry`) is registered automatically by a sidecar container in the APISIX pod on every install/upgrade — no manual step is required.

Create the ORDS route:

```bash
curl -i http://127.0.0.1:9180/apisix/admin/routes/<ords-resource-name> \
  -H "X-API-KEY: ${admin_key}" \
  -X PUT \
  -d '{
    "name": "<ords-resource-name>",
    "uri": "/ords/*",
    "methods": ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    "plugins": {
      "opentelemetry": {
        "sampler": {
          "name": "always_on"
        }
      }
    },
    "upstream": {
      "type": "roundrobin",
      "scheme": "https",
      "pass_host": "rewrite",
      "upstream_host": "localhost",
      "tls": {
        "verify": false
      },
      "nodes": {
        "<ords-resource-name>.<application-namespace>.svc.cluster.local:8443": 1
      }
    }
  }'
```

The route uses the ORDS HTTPS port, `8443`. The generated ORDS certificate uses `localhost`, so the APISIX upstream sets `upstream_host` to `localhost` and disables upstream certificate verification.

For a local test of the optional APISIX route, open a tunnel to the APISIX gateway:

```bash
kubectl -n <application-namespace> port-forward service/<app-release>-apisix-gateway 18080:80
```

Test the ORDS endpoint through APISIX:

```bash
curl -i \
  -H "x-request-id: ords-apisix-test-001" \
  http://localhost:18080/ords/<pool-name>/_/db-api/stable/
```

Check the APISIX route:

```bash
curl -s http://127.0.0.1:9180/apisix/admin/routes/<ords-resource-name> \
  -H "X-API-KEY: ${admin_key}"
```

In SigNoz, look for traces with service name `APISIX`. The APISIX span should include `http.route=/ords/*`, `apisix.route_id=<ords-resource-name>`, and `apisix.route_name=<ords-resource-name>`.
