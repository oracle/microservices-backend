# CloudBank Geographic Risk Service

`geographic-risk-service` is a Helidon microservice that evaluates location-based risk signals for a CloudBank loan application. It uses Oracle Spatial to compare an applicant's address coordinates against configured map areas, such as normal service areas, places where the product is not offered, boundary areas that need manual review, and synthetic location-risk zones used in the CloudBank demo.

The service is deterministic. It does not make credit decisions, reject loans, set pricing, generate adverse-action explanations, perform identity verification, run graph or relationship analysis, or use AI. It contributes location-aware evidence to MicroTx Workflows so downstream decisioning and manual-review services can act on clear, auditable signals.

## Source Layout

The source is organized by responsibility so workflow integration and Oracle
Spatial persistence remain separate from the HTTP boundary:

```text
com.cloudbank.geographicrisk
├── api           # JAX-RS resource and request/response models
├── application   # geographic-risk evaluation use case
├── domain        # dispositions, signals, and spatial evaluation models
├── persistence   # Oracle data access, entities, and generated repositories
├── security      # MP-JWT activation and internal-caller authorization
└── health        # readiness check
```

`GeographicRiskDatabase` remains the Oracle connection-context and Spatial
query adapter inside `persistence`. If its query surface expands materially,
split it into application-address, spatial-zone, and evaluation-query
repositories without exposing persistence details to `api` or `domain`.

## Workflow Role

MicroTx Workflows invokes this service after document review has confirmed that
usable address evidence is available and the document/policy evidence support
tasks have completed.

```text
Document Review -> AI/Policy Evidence -> Geographic Risk Service -> Relationship Risk Service -> Decision Service
```

Workflow version 1 implements the `evaluate_geographic_risk` protected HTTP
task. It uses the active runtime workflow authorization, a stable
`geo-risk:<applicationId>:<workflowId>` idempotency key, and the correlation-only
request documented below. The workflow exposes the returned evaluation ID and
disposition for the version-1 deterministic decision task.

The service should support the canonical CloudBank scenario:

```text
Manual Review: Relationship And Location Risk, application ID APP-RISK-005
```

For that scenario, the service should produce a clear location-review signal, such as `BOUNDARY_REVIEW_REQUIRED` or `LOCATION_RISK_REVIEW`.

## Responsibilities

- Evaluate applicant address coordinates against Oracle Spatial zones.
- Produce deterministic geographic risk signals.
- Return workflow-safe dispositions such as `CLEAR`, `MANUAL_REVIEW`, `BLOCKED`, or `NOT_EVALUATED`.
- Persist or expose geographic signal results for audit, workflow correlation, and observability.
- Emit trace-safe identifiers such as application ID, workflow ID, task reference, and trace ID.

## Non-Responsibilities

- No graph or relationship analysis.
- No identity verification decision.
- No loan approval, rejection, pricing, or adverse-action explanation.
- No AI-generated conclusions.
- No browser-facing API. Browser access should go through the future BFF.
- No zone-management API in the first version. Configured map areas should come from schema, migration, or seed data.

## Geographic Signals

Initial signal codes:

| Signal code | Meaning |
| --- | --- |
| `LOCATION_IN_SERVICE_AREA` | The applicant address is inside a configured normal service area. |
| `LOCATION_EXCLUDED` | The applicant address is inside a configured area where the product is not offered or the workflow cannot proceed automatically. |
| `BOUNDARY_REVIEW_REQUIRED` | The applicant address is close enough to a configured boundary to require manual review. |
| `LOCATION_RISK_REVIEW` | The applicant address intersects a synthetic location-risk zone used in the demo. |
| `ADDRESS_NOT_FOUND` | The service could not find address evidence for the application. |
| `ADDRESS_COORDINATES_MISSING` | Address evidence exists, but latitude/longitude or spatial geometry is missing; the result is `NOT_EVALUATED` without clearing the geographic check. |
| `SPATIAL_EVALUATION_UNAVAILABLE` | Spatial evaluation could not be completed because required spatial data or database capability is unavailable. |

Disposition values:

| Disposition | Meaning |
| --- | --- |
| `CLEAR` | No location signal requires workflow intervention. |
| `MANUAL_REVIEW` | Location evidence should be reviewed by a human or downstream review service. |
| `BLOCKED` | The workflow cannot safely continue until the location issue is resolved. This is not a loan rejection. |
| `NOT_EVALUATED` | The service did not evaluate location risk because required evidence was missing. Workflow version 1 routes this outcome to manual review. |

Routing effects:

| Routing effect | Meaning |
| --- | --- |
| `NONE` | No workflow routing change is needed. |
| `MANUAL_REVIEW` | Route or keep the application in manual review. |
| `BLOCKED` | Stop automatic workflow progress until the issue is resolved. |

## Schema

The geographic risk service should use the existing CloudBank schema objects under `src/schema`. These objects live in the shared `CLOUDBANK` schema and are installed by the `full-demo` schema profile because they depend on Oracle Spatial.

Primary objects:

```text
CB_LOAN_APPLICATION
CB_ADDRESS
CB_JURISDICTION_ZONE
CB_SPATIAL_SIGNAL
```

`CB_LOAN_APPLICATION` is the parent loan application record. The service receives an `applicationId`, resolves the application row, and uses its surrogate key when reading address evidence or writing signal rows.

`CB_ADDRESS` stores applicant address evidence. The optional spatial migration adds:

```sql
LOCATION_GEOM MDSYS.SDO_GEOMETRY
```

The geocoding migration adds optional `COUNTRY_CODE` and `POSTAL_CODE` address
parts. `JURISDICTION_CODE` remains the CloudBank zone-routing key and is not
interpreted as a country code.

`LOCATION_GEOM` is the applicant address point used for location checks.

When `LOCATION_GEOM` is missing, the service builds a complete address from
`ADDRESS_LINE`, `LOCALITY`, optional `POSTAL_CODE`, and optional `COUNTRY_CODE`
and calls `SDO_GCDR.ELOC_GEOCODE_AS_GEOM`. The returned point is used only for
the current evaluation; geographic-risk-service does not update `CB_ADDRESS`.
This preserves the loan-application service ownership boundary and its
read-only address grant. A missing geocoder match remains not evaluated, while
an unavailable or unauthorized GCDR call is routed to manual review.

For a short-lived geocoding diagnostic, change
`GEOGRAPHIC_RISK_LOG_GEOCODING_DETAILS` from `false` to `true` in the protected
repository-root `.env`, then run `./deploy/obaas/deploy-services.sh redeploy`.
When enabled, each GCDR attempt logs the exact
address passed to Oracle, returned longitude and latitude (or `null` for no
match), and `RESOLVED`, `NO_MATCH`, or `UNAVAILABLE`. Stored coordinates do not
trigger a GCDR diagnostic line. These fields can identify a person or location:
enable the flag only for a controlled test, restrict access to OKE/telemetry
logs, restore `false` in `.env`, and redeploy immediately afterward. The log
does not contain OAuth tokens or workflow inputs.

`CB_JURISDICTION_ZONE` stores configured map areas. Important columns include:

```text
ZONE_ID
JURISDICTION_CODE
ZONE_NAME
ZONE_TYPE
ZONE_STATUS
ZONE_GEOM
METADATA_JSON
```

`ZONE_GEOM` is the Oracle Spatial polygon or multipolygon that the applicant address is compared against. Current zone types are:

```text
ELIGIBLE_SERVICE_AREA
BOUNDARY_REVIEW
EXCLUDED_AREA
FRAUD_REVIEW_AREA
```

For this service, `FRAUD_REVIEW_AREA` should be treated in API and user-facing language as a synthetic location-risk zone, not as a fraud conclusion.

`CB_SPATIAL_SIGNAL` stores per-application geographic check results. Important columns include:

```text
APPLICATION_SK
ADDRESS_SK
JURISDICTION_ZONE_SK
SIGNAL_ID
SIGNAL_CODE
SIGNAL_TYPE
SIGNAL_RESULT
DISTANCE_TO_BOUNDARY_M
ROUTING_EFFECT
CREATED_AT
```

Current database signal types are:

```text
JURISDICTION_ELIGIBILITY
BOUNDARY_PROXIMITY
RISK_ZONE_INTERSECTION
```

Current database signal results are:

```text
PASS
REVIEW
FAIL
NOT_EVALUATED
```

Current database routing effects are:

```text
NONE
MANUAL_REVIEW
BLOCKED
```

The service uses `BLOCKED` in API and workflow language because this service does not reject loans. `SIGNAL_CODE` preserves public codes such as `ADDRESS_COORDINATES_MISSING` and `SPATIAL_EVALUATION_UNAVAILABLE` independently of the bounded database signal type.

Conceptually, the schema flow is:

```text
CB_ADDRESS.LOCATION_GEOM
  applicant location point

CB_JURISDICTION_ZONE.ZONE_GEOM
  configured service, review, excluded, or synthetic risk-area polygons

CB_SPATIAL_SIGNAL
  deterministic signal rows produced by geographic-risk-service
```

`CB_GEOGRAPHIC_RISK_EVALUATION` groups one service invocation and stores workflow correlation fields such as `EVALUATION_ID`, `APPLICATION_SK`, `WORKFLOW_ID`, `TASK_REFERENCE`, `TRACE_ID`, `IDEMPOTENCY_KEY`, `DISPOSITION`, and timestamps. `CB_SPATIAL_SIGNAL` stores the individual spatial signal rows and links them back to the evaluation through `GEOGRAPHIC_EVALUATION_ID`.

## APIs

All business APIs are internal service APIs. Callers must use CloudBank
service-to-service authentication and include workflow correlation identifiers.

### Internal API Authentication

The business endpoints require a bearer JWT issued by CloudBank `azn-server`.
The service validates the token signature through the configured JWKS endpoint,
issuer, and `cloudbank-api` audience. It then permits only an allow-listed
service caller with all of the following claims:

- `token_kind=service`;
- `scope` containing `cloudbank.internal`; and
- `client_id` listed in `GEOGRAPHIC_RISK_CALLER_CLIENT_IDS`, which defaults to
  `cloudbank-service-client` for the current workflow integration.

Health endpoints remain unauthenticated. Missing or invalid tokens receive
`401`; authenticated callers that do not meet the internal-caller policy
receive `403`.

`cloudbank-service-client` is an interim workflow-task identity, shared with
the current document extraction and review tasks. It is suitable for the
existing local and integration workflow contract, but it is not the intended
least-privilege end state. When the deployed MicroTx/OBaaS version has a
verified platform-managed task identity or token-exchange mechanism,
CloudBank should replace `workflowTaskAuthorization` with a short-lived,
task-scoped credential acquired at task execution time. Do not put a client
secret or a long-lived access token in workflow input.

### Create Geographic Risk Evaluation

```http
POST /internal/api/v1/geographic-risk/evaluations
Content-Type: application/json
Idempotency-Key: geo-risk:APP-RISK-005:WF-APP-RISK-005
```

Purpose: run the workflow-managed geographic risk evaluation for one loan application.

Request:

```json
{
  "applicationId": "APP-RISK-005",
  "workflowId": "WF-APP-RISK-005",
  "taskReference": "evaluate_geographic_risk",
  "traceId": "0123456789abcdef0123456789abcdef"
}
```

Response:

```json
{
  "applicationId": "APP-RISK-005",
  "workflowId": "WF-APP-RISK-005",
  "taskReference": "evaluate_geographic_risk",
  "service": "geographic-risk-service",
  "evaluationId": "GEO-EVAL-APP-RISK-005-001",
  "disposition": "MANUAL_REVIEW",
  "signals": [
    {
      "signalCode": "BOUNDARY_REVIEW_REQUIRED",
      "label": "Address near configured review boundary",
      "signalResult": "REVIEW",
      "routingEffect": "MANUAL_REVIEW",
      "zoneId": "ZONE-BOUNDARY-001",
      "zoneName": "Synthetic boundary review area",
      "distanceToBoundaryMeters": 82.4
    }
  ],
  "traceId": "0123456789abcdef0123456789abcdef"
}
```

Expected behavior:

- Repeating the same request with the same idempotency key should return the same evaluation result.
- Reusing the same idempotency key for a materially different request should return a conflict.
- Evaluation and signals commit together in a Helidon resource-local transaction.
  Concurrent inserts for the same application and idempotency key roll back the
  losing transaction and replay the committed winner in a fresh transaction;
  a different request hash returns HTTP `409` (`IDEMPOTENCY_CONFLICT`).
  If the winner cannot be retrieved, HTTP `503` (`EVALUATION_UNAVAILABLE`) includes
  `Retry-After: 1`. Unexpected errors return bounded JSON with HTTP `500`
  (`EVALUATION_FAILED`), without SQL, credentials, or request values.
  Error mapping is scoped to geographic-risk resource failures so Helidon's
  `/health/live` and `/health/ready` routing remains available to Kubernetes probes.
- An address row without coordinates returns `NOT_EVALUATED` with routing effect `NONE`; workflow version 1 routes that bounded uncertainty to manual review rather than treating it as a task fault or inventing a location result.

### Read Geographic Risk Evaluation

```http
GET /internal/api/v1/geographic-risk/evaluations/{evaluationId}
```

Purpose: retrieve a previously created geographic risk evaluation for internal diagnostics, audit support, or workflow troubleshooting.

Response:

```json
{
  "evaluationId": "GEO-EVAL-APP-RISK-005-001",
  "applicationId": "APP-RISK-005",
  "workflowId": "WF-APP-RISK-005",
  "taskReference": "evaluate-geographic-risk",
  "service": "geographic-risk-service",
  "disposition": "MANUAL_REVIEW",
  "signals": [
    {
      "signalCode": "BOUNDARY_REVIEW_REQUIRED",
      "label": "Address near configured review boundary",
      "signalResult": "REVIEW",
      "routingEffect": "MANUAL_REVIEW",
      "zoneId": "ZONE-BOUNDARY-001",
      "zoneName": "Synthetic boundary review area",
      "distanceToBoundaryMeters": 82.4
    }
  ],
  "traceId": "0123456789abcdef0123456789abcdef",
  "createdAt": "2026-07-13T14:30:00Z"
}
```

### Read Latest Application Geographic Risk

```http
GET /internal/api/v1/applications/{applicationId}/geographic-risk
```

Purpose: return the latest geographic risk result for a loan application so downstream services, audit views, or the future BFF can compose a role-safe summary.

Response:

```json
{
  "applicationId": "APP-RISK-005",
  "latestEvaluationId": "GEO-EVAL-APP-RISK-005-001",
  "disposition": "MANUAL_REVIEW",
  "signalCount": 1,
  "signals": [
    {
      "signalCode": "BOUNDARY_REVIEW_REQUIRED",
      "label": "Address near configured review boundary",
      "routingEffect": "MANUAL_REVIEW"
    }
  ]
}
```

### Health And Readiness

Helidon should expose standard health endpoints:

```text
GET /health
GET /health/live
GET /health/ready
```

Readiness should verify that the service can reach Oracle Database and that required geographic-risk objects are available, including spatial zone data and address geometry support when the full-demo schema profile is used.

## Minimal First Version

The first implementation should focus on the smallest useful workflow surface:

```text
POST /internal/api/v1/geographic-risk/evaluations
GET  /internal/api/v1/applications/{applicationId}/geographic-risk
GET  /health/ready
```

This is enough for MicroTx workflow integration, downstream service lookup, and operations visibility. Additional diagnostics can be added after the workflow contract stabilizes.

## Pre-requisites
As admin via ADB console, enable the schema user to run geocoding command:

```sql
EXEC SDO_GCDR.ELOC_GRANT_ACCESS('CB_GEOGRAPHIC_RISK_APP');
```

The ELOC GCDR functions are supported on Oracle Autonomous AI Database. The
local Oracle Free Compose profile continues to use stored fixture geometries;
GCDR-backed enrichment should be verified against the target Autonomous AI
Database environment.

## Build And Test Locally

Run the reactor commands from the repository root:

Compile and run the geographic risk service unit tests:

```bash
mvn -pl src/geographic-risk-service -am test
```

Build the service jar without running tests:

```bash
mvn -pl src/geographic-risk-service -am package -DskipTests
```

Build the service jar and run tests:

```bash
mvn -pl src/geographic-risk-service -am package
```

If your shell is already in `src/geographic-risk-service`, use the module-local commands instead:

```bash
mvn test
mvn package
mvn package -DskipTests
```

The unit tests use mocks and do not require a running Oracle Database. A local service startup does require a reachable Oracle Database with the CloudBank schema installed, including the Spatial-enabled objects from the `full-demo` schema profile.

## Run Locally With CloudBank

Use the normal repository workflow for local integration testing. The default `full-demo` profile provisions Oracle Spatial objects, the `CB_GEOGRAPHIC_RISK_APP` runtime account, the `svc-geographic-risk-service` database principal, the minimal `APP-RISK-005` fixture, and the Compose service on port `8083`.

Start from scratch:

```bash
./run-compose.sh purge --force
./run-compose.sh init --schema-profile full-demo
./run-compose.sh up
```

Run the full local verification suite:

```bash
./run-compose.sh verify
```

`verify` includes the geographic-risk API smoke test for `APP-RISK-005` and expects a `MANUAL_REVIEW` disposition with `BOUNDARY_REVIEW_REQUIRED`.

The smoke test also verifies that the business API rejects an anonymous call
and accepts a freshly minted `cloudbank-service-client` token:

```bash
GEOGRAPHIC_RISK_BASE_URL=http://127.0.0.1:8083 \
AZN_BASE_URL=http://127.0.0.1:8080 \
SERVICE_CLIENT_ID=cloudbank-service-client \
SERVICE_CLIENT_SECRET='<service-client-secret>' \
src/geographic-risk-service/smoke-test.sh
```

Check the service directly:

```bash
curl -s http://127.0.0.1:8083/health/ready
```

Example API call:

```bash
curl -s \
  -X POST http://127.0.0.1:8083/internal/api/v1/geographic-risk/evaluations \
  -H 'Content-Type: application/json' \
  -H 'Idempotency-Key: geo-risk-APP-RISK-005-WF-APP-RISK-005-001' \
  -d '{
    "applicationId": "APP-RISK-005",
    "workflowId": "WF-APP-RISK-005",
    "taskReference": "evaluate-geographic-risk",
    "traceId": "0123456789abcdef0123456789abcdef"
  }'
```

For host-side debugging without the Compose service, build the jar and reuse the generated `.env` values:

```bash
mvn -pl src/geographic-risk-service -am package
set -a
. ./.env
set +a

java \
  -Djavax.sql.DataSource.geographic-risk.connectionFactoryClassName='oracle.jdbc.pool.OracleDataSource' \
  -Djavax.sql.DataSource.geographic-risk.URL="jdbc:oracle:thin:@//localhost:1521/${ORACLE_SERVICE_NAME}" \
  -Djavax.sql.DataSource.geographic-risk.user='CB_GEOGRAPHIC_RISK_APP' \
  -Djavax.sql.DataSource.geographic-risk.password="${GEOGRAPHIC_RISK_DATASOURCE_PASSWORD}" \
  -jar src/geographic-risk-service/target/geographic-risk-service.jar
```

## Build For OBaaS

The service includes a `Dockerfile`, JKube configuration through the module `pom.xml`, and OBaaS Helm values in `values-obaas.yaml`.

Build the jar and container image for the default local registry:

```bash
mvn -pl src/geographic-risk-service -am package k8s:build
```

Build and push to an Oracle Cloud Infrastructure Registry repository:

```bash
mvn -pl src/geographic-risk-service -am package k8s:build k8s:push \
  -Dimage.registry=us-ashburn-1.ocir.io/<namespace>/cloudbank \
  -Dimage.tag=0.0.1-SNAPSHOT
```

If Rancher Desktop is being used on macOS, set `DOCKER_HOST` for the command.
Adjust the socket path for your local container runtime:

```bash
DOCKER_HOST=unix:///<path-to-your-docker-socket> \
mvn -pl src/geographic-risk-service -am package k8s:build k8s:push \
  -Dimage.registry=us-ashburn-1.ocir.io/<namespace>/cloudbank \
  -Dimage.tag=0.0.1-SNAPSHOT
```

The image repository and tag must match the `image.repository` and `image.tag` values used for the OBaaS Helm deployment.

## Deploy To OBaaS

`values-obaas.yaml` is intended for the OBaaS sample application Helm chart. It configures:

- the Helidon framework marker for OBaaS;
- the `geographic-risk` UCP datasource;
- service discovery;
- OpenTelemetry log and trace correlation;
- health, metrics, and service port settings;
- Kubernetes security context defaults;
- database authentication secret names.

Before deployment, confirm these environment-specific values:

```text
image.repository
image.tag
database.authN.secretName
database.privAuthN.secretName
GEOGRAPHIC_RISK_BOUNDARY_DISTANCE_METERS
AZN_ISSUER_URI
AZN_JWK_SET_URI
GEOGRAPHIC_RISK_CALLER_CLIENT_IDS
```

`AZN_ISSUER_URI` must exactly match the `iss` claim in access tokens. The JWKS
URI may use the cluster-local authorization-server route, but it must resolve
to the same signing keys. Never configure a client secret in this service just
to validate incoming JWTs.

Render the Helm manifest before applying it:

```bash
helm template geographic-risk-service \
  <path-to-obaas-sample-app-chart> \
  -f src/geographic-risk-service/values-obaas.yaml \
  -n obaas
```

Deploy or upgrade the service:

```bash
helm upgrade --install geographic-risk-service \
  <path-to-obaas-sample-app-chart> \
  -f src/geographic-risk-service/values-obaas.yaml \
  -n obaas
```

Check rollout and health:

```bash
kubectl get pods -n obaas -l app.kubernetes.io/name=geographic-risk-service
kubectl get svc -n obaas geographic-risk-service
kubectl logs -n obaas deploy/geographic-risk-service
```

If the OBaaS gateway route is not configured yet, test the service through a temporary port-forward:

```bash
kubectl port-forward -n obaas svc/geographic-risk-service 8080:8080
curl -s http://127.0.0.1:8080/health/ready
```

The service uses Logback Classic 1.5.38 with its standard pattern encoder to emit text logs to the console. The log pattern includes MDC fields such as application ID, workflow ID, task reference, geographic evaluation ID, and trace ID. In OBaaS, keep `OTEL_INSTRUMENTATION_LOGBACK_MDC_ENABLED=true` so logs and traces can be correlated in the observability stack.
