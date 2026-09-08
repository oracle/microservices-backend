# OBaaS And CloudBank Test Agent Runbook

This guide tells an AI agent how to deploy, test, collect evidence, and report on Oracle Backend for Microservices and AI (OBaaS) 2.1.2 with the CloudBank v5 sample workload.

The expected output of a test run is a completed report created from the template in this file, plus an evidence directory containing command output, logs, screenshots, and vulnerability scan results.

## Source Rules

Use only these sources for installation and test truth:

- `AGENTS.md` for OBaaS 2.1.2 planning, installation, and verification.
- `CBV5-AGENT.md` for CloudBank v5 deployment, testing, and cleanup.
- `docs-source/site/docs`, especially `intro.md`, `setup/helm/`, `platform/`, and `observability/`.
- `helm/infra-charts/obaas-prereqs` and `helm/infra-charts/obaas`.
- `cloudbank-v5/README.md`, `cloudbank-v5/cloudbank-v5-install.md`, and `cloudbank-v5/cloudbank-test-doc.md`.
- `cloudbank-v5/customer-helidon/README.md` when a mixed Spring Boot and Helidon CloudBank workload is required for observability testing.
- `cloudbank-v5/helidon-producer/README.md` and `cloudbank-v5/helidon-consumer/README.md` when Kafka observability or Helidon MP messaging telemetry must be validated.
- The task list provided with this guide.
- The SigNoz Services evidence checklist in this guide.

Use only the OBaaS `next` documentation stream for 2.1.2. Do not use 2.1.0 or older behavior, older CloudBank documentation, or unrelated repository directories.

Do not duplicate command syntax, values-file policy, secrets policy, or cleanup procedure from `AGENTS.md` or `CBV5-AGENT.md` in this file. If those guides conflict with this guide, treat them as canonical for deployment mechanics and treat this guide as canonical for test scope, evidence, and reporting.

## Required Inputs

Collect and record these values before any mutating command:

| Input | Description |
| --- | --- |
| `<kube-context>` | Kubernetes context selected for the run. |
| `<cluster-type>` | OKE, AKS, Rancher Desktop, another public cloud, or on-premises Kubernetes. |
| `<platform-system-namespace>` | Namespace for cluster-singleton prerequisites, for example `obaas-system`. |
| `<prereqs-release>` | Helm release for `obaas-prereqs`, for example `obaas-prereqs`. |
| `<application-namespace>` | Namespace for the OBaaS instance and CloudBank workload. |
| `<app-release>` | Helm release for the OBaaS application chart, for example `obaas`. |
| `<prereqs-values-file>` | Values file for the prerequisites chart, if any. |
| `<app-values-file>` | Values file for the OBaaS application chart. |
| `<obaas-chart-version>` | Expected local chart version, `0.1.2`, recorded from both local `Chart.yaml` files. |
| `<database-type>` | `SIDB-FREE`, `ADB-FREE`, `ADB-S`, or `OTHER`. |
| `<storage-class>` | StorageClass selected for persistent components. |
| `<access-path>` | Envoy Gateway by default, deprecated ingress-nginx when explicitly enabled, both, existing external access, or port-forward-only. |
| `<registry-mode>` | Public registries, private registry, air-gapped, OCIR, or local cluster images. |
| `<cloudbank-dbname>` | Database prefix used by CloudBank scripts. |
| `<cloudbank-image-tag>` | CloudBank image tag, default `0.0.1-SNAPSHOT`. |
| `<cloudbank-registry>` | Explicit image registry path, if not using OCIR auto-detection. |
| `<cloudbank-customer-implementation>` | `customer` for the Spring service, or `customer-helidon` when Helidon dashboard validation is required. |
| `<kafka-load-workload>` | Kafka load source when Kafka dashboards are required, for example `helidon-producer` and `helidon-consumer`. |
| `<eureka-replicas>` | Effective `eureka.replicas` value; default is `3`. |
| `<coherence-enabled>` | Whether the optional, deprecated Coherence cluster is enabled through `coherence.enabled`. |
| `<coherence-cluster-name>` | Effective Coherence CR name and persistence decision when Coherence is enabled. |
| `<otmm-coordinator-enabled>` | Whether the optional OTMM/MicroTx coordinator is enabled through `otmm.coordinator.enabled`. |
| `<otmm-workflow-server-enabled>` | Whether the optional MicroTx Workflow Server is enabled through `otmm.workflowServer.enabled`. |
| `<otmm-console-enabled>` | Whether the optional OTMM console is requested through `otmm.console.enabled`; it renders only when `otmm.coordinator.enabled` or `otmm.workflowServer.enabled` is also true. |
| `<priv-secret-name>` | Privileged DB secret, usually `<cloudbank-dbname>-db-priv-authn` unless customized. |
| `<evidence-dir>` | Directory for all run evidence and reports. |

Do not proceed with installation until these choices are known. Use placeholders in examples, but never install with unresolved placeholders.

## Cluster Policy

Use `AGENTS.md` as the source of truth for full OBaaS cluster prerequisites and capacity requirements.

Local functional testing may use a one-node cluster such as Rancher Desktop when the goal is smoke, sample workload, or developer-loop validation. In that case:

- Mark the run as `Local Functional`, not `Full Validation`.
- Record deviations from the documented cluster requirements.
- Prefer `SIDB-FREE` only if the node has enough CPU, memory, and ephemeral disk.
- Use port-forward evidence when no external load balancer is available.
- Treat capacity, HA, RWX storage, and external access tests as `Waived` only when the report includes the waiver reason.

## Evidence Layout

Create a fresh evidence directory before running tests:

```bash
export EVIDENCE_DIR=<evidence-dir>
mkdir -p \
  "$EVIDENCE_DIR/cluster" \
  "$EVIDENCE_DIR/helm" \
  "$EVIDENCE_DIR/obaas" \
  "$EVIDENCE_DIR/cloudbank" \
  "$EVIDENCE_DIR/observability" \
  "$EVIDENCE_DIR/security" \
  "$EVIDENCE_DIR/screenshots" \
  "$EVIDENCE_DIR/failures"
```

Capture stdout and stderr for every command that proves a result:

```bash
run_and_capture() {
  name="$1"
  shift
  "$@" >"$EVIDENCE_DIR/$name.out" 2>"$EVIDENCE_DIR/$name.err"
  status=$?
  echo "$status" >"$EVIDENCE_DIR/$name.status"
  return "$status"
}
```

For failures, also capture:

- `kubectl describe` for the failing resource.
- Current and previous pod logs.
- Related jobs and job logs.
- For cert-manager install failures, Helm status and history, cert-manager Job
  status/logs, deployment readiness, and cert-manager namespace events. Do not
  treat healthy pods as a passing result when the Helm release is pending or absent.
- For MicroTx Workflow Server failures, workflow server logs, health endpoint output, service/endpoints output, Helm values, latest `obaas-run-sql-*` job logs, and database privilege diagnostics for the application user.
- Namespace events sorted by time.
- Helm release status.
- APISIX route output when the failure involves gateway traffic.
- Full HTTP request command, response status, headers, and body.

## Execution Flow

This file does not own deployment mechanics. Use it to decide what must be tested and what evidence must be captured.

1. Prepare the evidence directory and report skeleton from this file.
2. Use `AGENTS.md` for all OBaaS preflight, chart-source selection, values preparation, cert-manager, `obaas-prereqs`, OBaaS install, uninstall, and reinstall commands.
3. After each OBaaS phase, return to the master test matrix in this file and record status, evidence paths, and failures.
4. Use `CBV5-AGENT.md` for all CloudBank v5 prerequisite checks, image handling, secret creation, service deployment, APISIX route creation, smoke tests, manual endpoint tests, and cleanup commands.
5. After each CloudBank phase, return to the master test matrix in this file and record status, evidence paths, and failures.
6. Use the observability, security, lifecycle, isolation, and report sections in this file for test coverage that is broader than either deployment guide.
7. Do not continue from OBaaS installation to CloudBank deployment until all required OBaaS health checks in the matrix are passing or explicitly waived.
8. Do not mark a test run complete until the report template in this file is filled out and all required evidence has been captured.

The exact commands, flags, values files, secret names, and cleanup procedures must come from `AGENTS.md` and `CBV5-AGENT.md` at execution time.

## Master Test Matrix

Use this matrix as the master list for each run. Mark each test `Pass`, `Fail`, `Waived`, or `Not Applicable`.

| ID | Category | Test | Expected Result | Evidence |
| --- | --- | --- | --- | --- |
| PRE-001 | Preflight | Verify current Kubernetes context. | Context equals `<kube-context>`. | `kubectl config current-context` |
| PRE-002 | Preflight | Verify cluster API access. | `kubectl get nodes` succeeds. | node list |
| PRE-003 | Preflight | Verify Helm access. | `helm version` and `helm list -A` succeed. | Helm output |
| PRE-004 | Preflight | Verify cluster capacity policy. | Full validation meets requirements, or local deviations are recorded. | node describe |
| PRE-005 | Preflight | Verify storage classes and RWX support decision. | Selected storage class and RWX status are recorded. | storageclass output |
| PRE-006 | Preflight | Verify external access strategy. | Envoy Gateway default, explicit ingress-nginx opt-in, both, or port-forward-only path is documented. | service, ingress, gateway output |
| PRE-007 | Preflight | Verify chart source and version. | Both local charts report chart version `0.1.2` and app version `2.1.2`; local paths are used unless public charts report app version `2.1.2`. | Chart.yaml and Helm search output |
| PRE-008 | Preflight | Render selected chart values. | `helm lint` and `helm template` succeed for both charts; rendered output reflects selected optional components. | lint and rendered-manifest output |
| INST-001 | Install | Install or verify cert-manager. | Helm reports `deployed`; cert-manager deployments are available; CRDs exist. A pending or missing Helm release is a failure even if pods are running. | Helm status, pod, wait, CRD output; on failure also capture Job logs and events |
| INST-002 | Install | Install `obaas-prereqs` once. | Release deployed and prerequisite pods healthy. | Helm status and pod output |
| INST-003 | Install | Install OBaaS. | Release deployed and OBaaS pods healthy. | Helm status and pod output |
| INST-004 | Install | Verify no unexpected failed jobs or PVC problems. | Jobs succeeded and PVCs bound. | jobs, PVCs, events |
| PLAT-001 | Platform | Verify APISIX gateway. | Gateway service has external address or working port-forward. | service output, curl result |
| PLAT-002 | Platform | Verify APISIX admin API. | Admin routes endpoint responds with valid admin key. | curl output |
| PLAT-003 | Platform | Verify Eureka. | Eureka UI/API is reachable. | screenshot and HTTP output |
| PLAT-004 | Platform | Verify Config Server. | `/<application>/<profile>` returns JSON property source response. | curl output |
| PLAT-005 | Platform | Verify Spring Boot Admin. | Admin UI is reachable and services appear. | screenshot |
| PLAT-006 | Platform | Verify database exporter. | Exporter pod/service is healthy and metrics scrape target exists. | pod, service, logs |
| PLAT-007 | Platform | Verify optional OTMM/MicroTx coordinator runtime. | When enabled, OTMM service is healthy and CloudBank transfer can use the LRA coordinator; otherwise marked `Not Applicable` with values evidence. | Helm values, pod output, CloudBank transfer evidence |
| PLAT-008 | Platform | Verify optional Kafka. | Kafka CRs and dashboard data exist when Kafka is enabled. | Strimzi/Kafka output |
| PLAT-009 | Platform | Verify optional AI Optimizer. | AI Optimizer pods and required secrets exist when enabled. | pod, secret output |
| PLAT-010 | Platform | Verify optional MicroTx Workflow Server. | When enabled, workflow server is healthy, Flyway migration succeeds, and no Oracle privilege error is present; otherwise marked `Not Applicable` with values evidence. | Helm values, pod, service, health endpoint, logs |
| PLAT-011 | Platform | Verify optional OTMM console. | When `otmm.console.enabled=true` and either coordinator or workflow server is enabled, console is healthy and reachable at `/consoleui/`; otherwise marked `Not Applicable` with values evidence. | Helm values, pod, service, `/consoleui/` HTTP output, screenshot |
| PLAT-012 | Platform | Verify APISIX OpenTelemetry runtime metadata. | The `apisix-plugin-metadata` sidecar reports success and the APISIX Admin API returns OpenTelemetry plugin metadata. | sidecar logs and Admin API output |
| PLAT-013 | Platform | Verify Eureka/APISIX replica alignment. | The APISIX Eureka discovery host list contains one StatefulSet-pod endpoint for every effective Eureka replica. | Helm values, rendered ConfigMap, running ConfigMap |
| PLAT-014 | Platform | Verify optional Coherence cluster. | When enabled, the operator and CRD are ready and the release-owned Coherence CR reaches its requested member count; otherwise marked `Not Applicable` with values evidence. | Helm values, CRD/operator, Coherence CR and pod output |
| CB-001 | CloudBank | Run CloudBank prerequisite checks. | Build and deploy checks pass. | script output |
| CB-002 | CloudBank | Build and publish or load images. | Images for the selected CloudBank services are available to the cluster. | build/push output |
| CB-003 | CloudBank | Create CloudBank secrets. | Expected DB, OAuth, and signing-key secrets exist. | secret list |
| CB-004 | CloudBank | Deploy seven services. | `azn-server`, `account`, selected customer implementation, `creditscore`, `transfer`, `checks`, `testrunner` are running. | Helm and pod output |
| CB-005 | CloudBank | Create APISIX routes. | Required routes created and sensitive routes blocked. | route script output |
| CB-006 | CloudBank | Run secured smoke test. | Smoke test passes. | smoke script output |
| CB-007 | CloudBank | Check OAuth metadata and JWKS. | Metadata is public and JWKS exposes a key ID. | curl output |
| CB-008 | CloudBank | Check unauthorized access. | Protected endpoint without token returns `401`. | curl output |
| CB-009 | CloudBank | Check read access. | Read token can call account, customer, and creditscore APIs. | curl output |
| CB-010 | CloudBank | Check wrong-scope access. | Wrong token scope returns `403`. | curl output |
| CB-011 | CloudBank | Check deposit workflow. | Deposit returns success and check service logs show receipt. | curl and logs |
| CB-012 | CloudBank | Check journal and clearance workflow. | Journal moves from pending to deposit after clear. | curl and logs |
| CB-013 | CloudBank | Check transfer workflow. | Balances change correctly and transfer logs show LRA lifecycle. | curl and logs |
| CB-014 | CloudBank | Run full all-services validation. | `7-test_all_services.sh` passes for `Full Validation`; local-functional runs may mark it `Not Applicable` with tier evidence. | full script output |
| OBS-001 | Observability | Log in to SigNoz. | SigNoz UI login succeeds. | screenshot |
| OBS-002 | Observability | Verify SigNoz Services view. | Platform and CloudBank services appear for recent time window. | screenshot |
| OBS-003 | Observability | Verify Services table columns. | P99 latency, error rate, and operations per second are populated. | screenshot |
| OBS-004 | Observability | Verify traces. | CloudBank request traces appear and can be opened. | screenshot |
| OBS-005 | Observability | Verify logs. | CloudBank and platform logs appear and can be filtered by namespace/pod/service. | screenshot |
| OBS-006 | Observability | Verify metrics. | Service metrics are visible for CloudBank and platform services. | screenshot |
| OBS-007 | Observability | Verify infra monitoring. | Kubernetes node, pod, PVC, and host metrics are visible where supported. | screenshot |
| OBS-008 | Observability | Verify dashboards are installed. | Expected preinstalled dashboards are present. | screenshot and dashboard list |
| OBS-009 | Observability | Verify dashboard population. | Key dashboards show current data after generated traffic. | screenshots |
| OBS-010 | Observability | Verify DB observability. | Oracle Database and DB Calls dashboards show data. | screenshots |
| OBS-011 | Observability | Verify APISIX observability. | APISIX dashboard shows gateway request data. | screenshot |
| OBS-012 | Observability | Verify JVM/Spring observability. | Spring Boot and JVM dashboards show CloudBank data. | screenshots |
| OBS-013 | Observability | Verify optional MicroTx observability. | When `otmm.coordinator.enabled=true`, MicroTx dashboard shows data after transfer workflow or waiver explains absence; when disabled, mark `Not Applicable` with values evidence. | screenshot or values evidence |
| OBS-014 | Observability | Verify messaging queues view. | Messaging Queues view is accessible and populated when queue/Kafka data exists. | screenshot |
| OBS-015 | Observability | Verify telemetry data before dashboard capture. | Metrics, logs, and traces exist for required services in the selected time window before screenshots are taken. | curl/API/SQL output |
| OBS-016 | Observability | Validate captured screenshots. | Screenshot guardrails prove the expected page was captured and required dashboards contain data. | validation report |
| OBS-017 | Observability | Verify collector scrape health. | Collector logs show EndpointSlice-based kube-state-metrics discovery with no repeated collector self-scrape or deprecated v1 endpoint warnings. | current and previous collector logs, scrape evidence |
| SEC-001 | Security | Scan OBaaS images. | Scanner completes and critical/high findings are triaged. | scan report |
| SEC-002 | Security | Scan CloudBank images. | Scanner completes and critical/high findings are triaged. | scan report |
| SEC-003 | Security | Record scanner metadata. | Scanner name, version, DB date, image tags, and digests are recorded. | scan output |
| LIFE-001 | Lifecycle | Uninstall OBaaS chart when explicitly approved. | Namespace-scoped resources are removed or expected retained resources are documented. | Helm/kubectl output |
| LIFE-002 | Lifecycle | Reinstall OBaaS into same namespace. | Install succeeds after cleanup. | Helm/kubectl output |
| MT-001 | Multi-OBaaS | Install second OBaaS in different namespace. | Second release is healthy. | Helm/kubectl output |
| MT-002 | Multi-OBaaS | Verify Eureka isolation. | Each Eureka instance sees only its namespace's services. | screenshots |
| MT-003 | Multi-OBaaS | Verify SigNoz isolation. | Each SigNoz instance shows only its namespace's telemetry. | screenshots |
| DB-001 | BYODB | Test `database.type: OTHER` when available. | OBaaS installs against BYODB and required grants are verified. | SQL and Helm output |

## Functional Test Guidance

Use `AGENTS.md`, `CBV5-AGENT.md`, and the local platform documentation for exact commands. This section defines only the additional system-test expectations.

Platform checks:

- APISIX gateway must be reachable through the selected access path or a documented local port-forward.
- APISIX admin API must show the route set expected after CloudBank route creation.
- APISIX OpenTelemetry metadata must be configured by the `apisix-plugin-metadata` sidecar and retrievable from the Admin API before APISIX tracing is marked healthy.
- Eureka must show the OBaaS platform services and all selected CloudBank services after deployment. Record the effective `eureka.replicas` value and verify that APISIX lists a numbered StatefulSet-pod host for every replica; changing the replica count without updating that list is a failure.
- Config Server must respond. If no test property is seeded, record that the server is reachable and that no config data validation was performed.
- Spring Boot Admin must show monitored Spring services and health status.
- OTMM/MicroTx coordinator is optional and controlled by `otmm.coordinator.enabled`. Test the coordinator runtime on every run where it is enabled or installed. If it is disabled, mark the related rows `Not Applicable` and preserve values evidence proving it was disabled. If MicroTx is known to fail in the tested OBaaS build, do not skip the test when enabled; run it, mark the status `Fail` or `Waived` according to operator policy, and record the version-specific failure, logs, workflow output, and recommended retest trigger.
- The optional MicroTx Workflow Server is a separate test surface from the coordinator runtime. When `otmm.workflowServer.enabled=true`, preserve Helm values proving the option is enabled, deployment and pod readiness, service/endpoints output, `/workflow-server/health` output, and workflow server logs.
- Workflow server logs must show successful startup and successful Flyway schema migration or validation. Search and record whether the logs contain `ORA-01031`, `FlywayException`, failed database login, missing database secret, or missing service-name evidence.
- The MicroTx Workflow Server uses the OBaaS application database secret and application schema. If Flyway DDL fails, collect the latest `obaas-run-sql-*` job logs and verify the application user has schema DDL privileges and quota before marking the issue as an application failure.
- Treat the optional OTMM console as a separate component. The console web UI is served from `/consoleui/` on the `obaas-otmm-console` service, not from the service root. For example, from inside the cluster use `http://obaas-otmm-console.<application-namespace>.svc.cluster.local:5001/consoleui/`; with a local port-forward use `kubectl -n <application-namespace> port-forward svc/obaas-otmm-console 15001:5001` and open `http://127.0.0.1:15001/consoleui/`. The service root `/` may return `404 Endpoint not found` and should not by itself be treated as console failure. Do not use a healthy console screenshot as evidence that the workflow server is installed or that workflow database migrations succeeded.
- Coherence is optional and deprecated. When `coherence.enabled=true`, verify the cluster-wide Coherence Operator deployment and CRD before installing, then verify the release-owned Coherence CR, requested member pods, namespace watch scope, and persistence decision. When disabled, mark `PLAT-014` as `Not Applicable` with values evidence.

CloudBank checks:

- Run the automated secured smoke test from `CBV5-AGENT.md` first and preserve its full output.
- For `Full Validation`, run and preserve the output of `cloudbank-v5/7-test_all_services.sh` after the smoke test. A `Local Functional` run may mark this test `Not Applicable` only when the report records that tier and reason.
- For CloudBank all-services tests, account IDs used with `--from-account` and `--to-account` must be accounts visible to the `--owner-username` user token used by the script. Do not guess seeded account IDs across environments. Prefer letting `cloudbank-v5/7-test_all_services.sh` auto-discover accounts, or first run it with `--read-only` and reuse the reported `account discovery from=<id> to=<id>` pair for the full mutating run.
- When the run must validate Helidon observability, deploy `customer-helidon` instead of the Spring `customer` service so the workload includes both Spring Boot and Helidon services.
- Use `CBV5-AGENT.md` for the standard CloudBank deployment flow and `cloudbank-v5/customer-helidon/README.md` only for the `customer-helidon` build, values, deployment, and service-specific verification details.
- When `customer-helidon` is selected, preserve evidence that the `/api/v1/customer*` route targets the Helidon customer service and that customer API smoke tests still pass.
- If no Helidon workload is deployed, mark Helidon dashboards `Not Applicable`; do not fail them for showing no data.
- This repository currently has Helidon MP examples, not Helidon SE examples. Treat `Helidon SE Details` as `Not Applicable` or `Waived: no Helidon SE workload in this run` unless a real Helidon SE workload has been deployed.
- Run any additional manual endpoint checks from `cloudbank-v5/cloudbank-test-doc.md` only when they add evidence not already covered by the smoke test.
- Verify OAuth metadata and JWKS reachability, unauthorized access rejection, wrong-scope rejection, read-token success, deposit/journal/clearance behavior, transfer behavior, and expected workflow logs.
- Use HTTPS for external gateway URLs. Use local port-forwarding only for local test clusters or isolated evidence capture.

Screenshots:

- Capture Eureka and Spring Boot Admin UI evidence with Selenium or an equivalent browser automation tool.
- For any UI that cannot be captured, record the exact access method used, browser or automation error, related service state, and related logs.

## Observability Test Requirements

Use the following SigNoz Services checklist as the minimum UI evidence requirement for enterprise observability validation.

### Telemetry Data Readiness

Do not start dashboard screenshot capture until the run has proved that relevant telemetry exists for the selected time window. Empty dashboards are not acceptable evidence for required observability tests unless the dashboard is for an optional component that was not installed or the report includes an explicit waiver.

Before UI capture, use curl, SigNoz API calls from an authenticated browser/session, ClickHouse queries, service metrics endpoints, or other direct telemetry checks to prove data is present. Save all command output under `$EVIDENCE_DIR/observability`.

Required readiness checks:

- Services: prove recent service telemetry exists for OBaaS platform services and all deployed CloudBank services.
- Traces: prove at least one recent CloudBank trace exists and includes more than one CloudBank service when a workflow crosses services.
- Logs: prove recent logs exist for `<application-namespace>` and at least one CloudBank service.
- Metrics: prove recent metric series exist for HTTP traffic, JVM, Spring, Helidon when deployed, APISIX or gateway traffic, Kubernetes pod or node metrics, and database metrics where those components are installed.
- Collector logs: when OpenTelemetry collectors are deployed, collect current and previous logs for the SigNoz collector, the k8s-infra collector deployment, and the k8s-infra collector agent pods before marking observability evidence complete. Confirm kube-state-metrics discovery uses EndpointSlices and investigate repeated collector self-scrape failures or deprecated v1 endpoint warnings; neither may be present in a passing `OBS-017` result.
- Dashboard-specific data: for every required dashboard screenshot, identify at least one metric, trace, log query, or table on that dashboard that has data before capture.
- Screenshot-specific data: after capture, inspect the screenshot companion DOM text and validation metadata for each required dashboard. A dashboard page load is not enough; the validation artifact must show at least one data-bearing panel, table row, plotted series, legend, service name, endpoint, metric value, or non-zero/current sample that matches the dashboard's purpose.

Acceptable direct evidence examples:

```bash
curl -sS <signoz-or-query-api-url> >"$EVIDENCE_DIR/observability/signoz-services-data.json"
curl -sS <cloudbank-service-actuator-prometheus-url> >"$EVIDENCE_DIR/observability/cloudbank-actuator-prometheus.txt"
kubectl -n <application-namespace> exec <clickhouse-pod> -- clickhouse-client --query '<read-only-query>' >"$EVIDENCE_DIR/observability/clickhouse-telemetry-check.txt"
```

The exact SigNoz API and ClickHouse schema may vary by chart version. Record the query or API path used, the time window, the response status, and enough response data to prove the count is greater than zero.

### Telemetry Load Generation

If any required telemetry readiness check returns no data, generate load before taking screenshots. Do not mark an empty required dashboard as passing just because the page loaded.

Use CloudBank traffic first because it exercises the most useful path through APISIX, OAuth, Spring Boot services, database calls, traces, logs, and JVM metrics:

- Run the CloudBank secured smoke test from `CBV5-AGENT.md`.
- Repeat read endpoints for account, customer, creditscore, and OAuth metadata. If `customer-helidon` is selected, customer endpoint traffic must route to the Helidon customer service.
- Run deposit, journal, check clearance, and transfer workflows.
- Prefer a short loop, for example 5 to 10 minutes, with modest concurrency that the local cluster can sustain.
- Capture the exact load command, start and end timestamps, request counts, HTTP status summary, and any errors.
- Continue or repeat load generation until the required readiness checks for the target dashboards return data, or until a bounded timeout is reached and the report records the remaining dashboard as `Fail`, `Partial`, `Waived`, or `Not Applicable` with the exact reason.
- Capture required dashboards shortly after the readiness checks pass. If the selected time window is `Last 30 minutes`, make sure load occurred inside that window; prefer capturing while a light traffic loop is still running for HTTP, APISIX, service, and JVM dashboards.

Map generated load to dashboard expectations:

| Dashboard or View | Data To Generate Before Capture |
| --- | --- |
| SigNoz Services, APM Metrics, HTTP API Monitoring | Repeated CloudBank API requests through APISIX. |
| Apache APISIX and Envoy Gateway by default; NGINX only when ingress-nginx is explicitly enabled | Gateway-routed CloudBank API requests. |
| Spring Boot Observability, Spring Boot 3.x Statistics, JVM Metrics | CloudBank service requests plus actuator or metrics scraping evidence. |
| DB Calls Monitoring, Oracle Database Dashboard | CloudBank account, deposit, journal, and transfer operations that touch the database. |
| MicroTx | CloudBank transfer workflow for coordinator/LRA telemetry when `otmm.coordinator.enabled=true`; MicroTx Workflow Server health, logs, and metrics when `otmm.workflowServer.enabled=true`. |
| Logs and Traces | CloudBank smoke and workflow requests with trace propagation enabled. |
| Kubernetes Pod, Node, PVC, Host, kube-state-metrics | Wait for collector scrape intervals and verify pod/node/PVC metrics directly. |
| Kafka Server Monitoring Dashboard | Kafka producer/consumer traffic when Kafka is enabled. Prefer `helidon-producer` and `helidon-consumer` with repeated `POST /post` requests to `my-topic`. |
| Helidon MP dashboards | `customer-helidon` customer API requests, `helidon-producer` Kafka publish requests, or `helidon-consumer` message consumption when those workloads are deployed. |
| Helidon SE dashboards | A real Helidon SE workload. If none is deployed, mark the dashboard `Not Applicable` or `Waived` with the reason `no Helidon SE example/workload in this run`. |

After load generation, wait for the collector and SigNoz ingestion lag to settle, then rerun telemetry readiness checks. A typical wait is 1 to 3 minutes on a local cluster, but use observed ingestion behavior rather than a fixed assumption.

### Kafka Load Generation

When Kafka is enabled and Kafka dashboards are required, do not accept an empty Kafka dashboard until load has been attempted and diagnostics have been captured.

Preferred load path:

1. Deploy `helidon-producer` and `helidon-consumer` using their local README files and values files.
2. Confirm their values set `OTEL_INSTRUMENTATION_KAFKA_METRICS_ENABLED=true`.
3. Confirm the Kafka bootstrap service and topic values match the installed Strimzi Kafka cluster.
4. Send repeated `POST /post` requests to the producer service.
5. Confirm producer logs show messages sent and consumer logs show messages consumed.
6. Verify Kafka producer or consumer metrics exist before taking Kafka dashboard screenshots.

Example local-cluster load loop:

```bash
for i in $(seq 1 200); do
  curl -sS -X POST \
    -H "Content-Type: text/plain" \
    --data "obaas-kafka-load-${i}-$(date -u +%Y%m%dT%H%M%SZ)" \
    http://<helidon-producer-url>/post
  echo
  sleep 1
done >"$EVIDENCE_DIR/observability/kafka-load-curl.out" \
  2>"$EVIDENCE_DIR/observability/kafka-load-curl.err"
```

If a gateway route is not available for `helidon-producer`, use a local port-forward only for evidence capture:

```bash
kubectl -n <application-namespace> port-forward svc/helidon-producer 18080:80
```

Kafka readiness evidence must include:

- `kubectl get kafka,kafkatopic,pods,svc -n <application-namespace>` output when the CRDs are available.
- Producer and consumer pod logs showing send and consume activity.
- Direct telemetry evidence for producer or consumer metrics, such as `kafka.producer.*`, `messaging.kafka.producer.*`, `kafka.consumer.*`, or `messaging.kafka.consumer.*`.
- Kafka dashboard screenshot validation after the load and ingestion wait.

If Kafka is enabled but `helidon-producer` and `helidon-consumer` are not deployed, use an equivalent producer/consumer or Strimzi client pod to generate topic traffic and record the exact commands. If no Kafka-producing workload is available, mark Kafka dashboard population `Fail` for a full observability run or `Waived` only with operator approval.

### SigNoz Services Checklist

Capture the SigNoz UI on the `Services` page with these visible elements:

- SigNoz Enterprise branding.
- The displayed SigNoz version.
- Left navigation with `Services` selected.
- Left navigation entries for `Traces`, `Logs`, `Metrics`, `Infra Monitoring`, `Dashboards`, and `Messaging Queues`.
- A top refresh indicator showing a recent refresh, for example `Refreshed 8 sec ago`.
- Time range set to `Last 30 minutes`.
- Refresh and share controls visible.
- A resource attribute search/filter bar above the table.
- A services table with sortable columns:
  - service name
  - `P99 latency (in ms)`
  - `Error Rate (% of total)`
  - `Operations Per Second`
- Multiple service rows with numeric latency, error-rate, and operations-per-second values.

Evidence requirements:

- Capture the page after CloudBank traffic has been generated.
- Use a recent time window, preferably `Last 30 minutes`.
- Ensure the screenshot includes the refresh timestamp, selected time range, service rows, and the `P99 latency (in ms)`, `Error Rate (% of total)`, and `Operations Per Second` columns.
- The service-name column must be readable. If names are cropped or hidden, take another screenshot with the sidebar collapsed, a wider viewport, or horizontal scroll adjusted.
- At least the CloudBank services and OBaaS platform services should appear in the services list after traffic and platform checks.
- Numeric values must be present, not blank or `No data`.
- `Operations Per Second` values of `0.00` are acceptable only when the report also includes curl or smoke-test evidence proving traffic occurred within the selected time range. Prefer capturing the screenshot while traffic is active so at least some services show non-zero operations per second.
- Error-rate values must be explained. Expected negative tests such as `401` and `403` may contribute to visible error rates; unexplained high error rates must be investigated with logs, traces, and failed HTTP evidence.

### Access SigNoz

Use the SigNoz access procedure from `docs-source/site/docs/observability/access.md` for the current chart version and selected release name. Record the credential source, access method, and URL in the run report without printing passwords into committed files.

### Required SigNoz Screenshots

Capture evidence for:

- Services list with platform and CloudBank services.
- Services table showing P99 latency, error rate, and operations per second.
- A CloudBank service metrics detail page.
- Traces list filtered to CloudBank traffic.
- A trace detail page showing cross-service timing.
- Logs filtered by `<application-namespace>` and at least one CloudBank service.
- Log detail page showing context and trace correlation when available.
- Metrics explorer or service metrics view.
- Infra Monitoring view for Kubernetes nodes, pods, PVCs, or host metrics.
- Dashboards list showing preinstalled dashboards.
- At least these populated dashboards after generated traffic:
  - Spring Boot Observability
  - Spring Boot 3.x Statistics
  - Oracle Database Dashboard
  - kube-state-metrics-v2
  - Apache APISIX
  - Envoy Gateway Dashboard, if Envoy Gateway is enabled
  - APM Metrics
  - Kubernetes Pod Metrics - Overall
  - Kubernetes Pod Metrics - Detailed
  - Kubernetes PVC Metrics
  - Kubernetes Node Metrics - Overall
  - Kubernetes Node Metrics - Detailed
  - DB Calls Monitoring
  - Host Metrics (k8s)
  - HTTP API Monitoring
  - JVM Metrics
  - NGINX (OTEL), if ingress-nginx is enabled
- MicroTx dashboard, if `otmm.coordinator.enabled=true`, after CloudBank transfer workflow load has been generated
- Kafka Server Monitoring Dashboard, if Kafka is enabled, after producer/consumer load has been generated
- Helidon Main Dashboard, Helidon MP Details, and Helidon JVM Details, only when `customer-helidon`, `helidon-producer`, `helidon-consumer`, or another Helidon MP workload is deployed
- Helidon SE Details only when a real Helidon SE workload is deployed; otherwise mark it `Not Applicable` or `Waived` because this repository currently provides Helidon MP examples only

For the Helidon JVM Details dashboard, validate `Peak Active Virtual Threads` and `Peak Pinned Virtual Threads` as window-maximum panels. Do not treat those panels as instantaneous active or pinned thread counts.

### Dashboard Detail Capture Requirements

The dashboards list page proves only that dashboards are installed. It does not prove that any individual dashboard was opened or populated.

Capture exactly one dashboards-list screenshot for `OBS-008`. For each named dashboard required by `OBS-009` through `OBS-014`, capture a separate dashboard-detail screenshot.

Before saving a named dashboard screenshot, the browser automation must verify:

- The final browser URL is a dashboard detail route, not the dashboards list route. For SigNoz this means a URL shaped like `/dashboard/<dashboard-id>` rather than only `/dashboard`.
- The visible dashboard title or breadcrumb matches the expected dashboard name.
- The page is not still on `All Dashboards`, `Dashboards`, or `Create and manage dashboards for your workspace`.
- The expected dashboard-specific content is visible, such as variables, panels, legends, table headings, or metric labels from that dashboard.
- The dashboard has finished loading or has been refreshed after navigation.

Recommended capture sequence for each named dashboard:

1. Start from the dashboards list and search for the exact dashboard title.
2. Click the dashboard row or link.
3. Wait until the URL changes to a dashboard detail route and the expected dashboard title is visible.
4. Run telemetry and screenshot validation checks.
5. Save the screenshot only after validation passes.

If the click does not leave the dashboards list, retry with a more direct navigation method. Acceptable fallback methods include opening the link discovered in the DOM, using the dashboard ID from an authenticated SigNoz API response, or using the dashboard ID visible in the browser URL after a manual successful click. Record the fallback method in the validation artifact.

If the automation still captures the dashboards list page for a named dashboard, mark that dashboard screenshot `Fail`, keep the failed screenshot as diagnostic evidence, and recapture before the run can pass.

### Selenium Evidence Capture

Use Selenium WebDriver or an equivalent Selenium-compatible driver. Store screenshots under `$EVIDENCE_DIR/screenshots`.

Minimum screenshot naming convention:

```text
screenshots/signoz-01-login.png
screenshots/signoz-02-services.png
screenshots/signoz-03-service-detail-cloudbank.png
screenshots/signoz-04-traces.png
screenshots/signoz-05-trace-detail.png
screenshots/signoz-06-logs.png
screenshots/signoz-07-dashboards-list.png
screenshots/signoz-08-dashboard-spring-boot-observability.png
screenshots/signoz-09-dashboard-http-api.png
screenshots/signoz-10-dashboard-db-calls.png
screenshots/signoz-11-dashboard-helidon-main.png
screenshots/signoz-12-dashboard-helidon-mp.png
screenshots/eureka-services.png
screenshots/spring-boot-admin-services.png
screenshots/apisix-dashboard.png
```

### Screenshot Validation Guardrails

Every automated screenshot capture must produce a companion validation artifact under `$EVIDENCE_DIR/observability`, for example `screenshot-validation.json` or `screenshot-validation.md`.

For each screenshot, record:

- Expected view or dashboard name.
- Screenshot file path.
- Browser URL after navigation.
- Page title or visible heading text captured from the DOM.
- Time range selected in the UI.
- Whether the page is authenticated and not redirected to login.
- Whether the page contains obvious error states such as `404`, `500`, `unauthorized`, `failed to load`, or a blank root element.
- Whether the screenshot is non-empty and visually plausible, using at least a file-size and image-dimension check.

For dashboard screenshots, also record:

- Dashboard title matched the expected title.
- The browser URL is a dashboard detail URL, not only the dashboards list. For SigNoz, `/dashboard` is the list view and must not pass for a named dashboard; `/dashboard/<dashboard-id>` is expected.
- The DOM text does not identify the page as only the dashboards list, such as `All Dashboards` without the expected dashboard detail heading.
- Count of visible `No Data` panels.
- Count of visible `No data` or equivalent empty-state panels normalized case-insensitively.
- Count or examples of visible numeric values, table rows, chart legends, service names, or plotted series.
- The dashboard population classification: `populated`, `partial`, `empty`, `zero-only`, or `not-applicable`.
- For `partial` dashboards, the panel or data-bearing evidence that justifies accepting the screenshot and the specific empty panels that remain.
- The direct telemetry readiness evidence file that proves backing data existed before the screenshot was captured.

Pass/fail rules:

- A required dashboard screenshot fails when the expected dashboard title is missing.
- A required dashboard screenshot fails when the captured page is the dashboard list, login page, error page, or a blank page.
- A required dashboard screenshot fails when its final URL is only the dashboards list route, even if the expected dashboard name appears in the list.
- A required dashboard screenshot fails when all meaningful panels show `No Data`, blank panels, or zero-only values after load generation.
- A required dashboard screenshot fails when the validation artifact cannot identify at least one dashboard-relevant populated panel or data row after load generation.
- A screenshot may pass with some `No Data` panels only when at least one relevant panel is populated and the report explains why the empty panels are expected.
- A screenshot should be marked `Partial`, not `Pass`, when it contains useful data but also has prominent empty panels that need follow-up.
- Optional dashboards for disabled components must be marked `Not Applicable`, not `Pass`.

Recommended guardrail implementation:

- Use Selenium to capture both the screenshot and page DOM text.
- Save DOM text next to the screenshot, for example `screenshots/<name>.txt`.
- Use browser assertions before saving the screenshot: expected heading present, expected dashboard-detail URL pattern, expected time range, and at least one data-bearing selector or text value present.
- Save the final URL for every screenshot in the validation artifact. This is mandatory for distinguishing a dashboard list screenshot from a dashboard detail screenshot.
- Parse the saved DOM text for empty-state phrases such as `No Data`, `No data`, `No logs found`, `No traces found`, `No metrics found`, and `There is no data`. Store those counts in the validation artifact.
- Parse the saved DOM text for dashboard-specific positive evidence such as CloudBank service names, HTTP endpoint rows, APISIX request counters, JVM CPU or memory samples, Oracle DB metric samples, MicroTx transaction widgets, Helidon MP memory or HTTP request panels, or non-zero request/operation counts.
- Optionally run OCR or image analysis after capture to catch cases where the DOM looked correct but the image is blank, off-screen, or still loading.
- Re-capture after refreshing the dashboard if validation fails because panels are still loading.
- If a recapture still shows an empty required dashboard after telemetry readiness checks pass, preserve both the failed screenshot and the direct telemetry evidence, then mark the dashboard `Fail` or `Partial` according to the positive evidence visible in the screenshot.

If a UI cannot be accessed, mark the related test `Fail` and capture:

- Port-forward command output.
- Browser or Selenium error.
- Related service, pod, and endpoint output.
- Related logs.

## Vulnerability Scanning

Scan all OBaaS and CloudBank images that are deployed or rendered by the selected values files.

Use Trivy by default:

```bash
trivy version
trivy image --format json --output "$EVIDENCE_DIR/security/<image-name>.trivy.json" <image-ref>
trivy image --severity CRITICAL,HIGH --exit-code 1 <image-ref>
```

Use Grype as fallback when Trivy is unavailable:

```bash
grype version
grype -o json <image-ref> >"$EVIDENCE_DIR/security/<image-name>.grype.json"
grype --fail-on high <image-ref>
```

For each image, record:

- Scanner name and version.
- Scanner vulnerability database date, when available.
- Image reference.
- Image digest, when available.
- Total vulnerabilities by severity.
- Critical, high, and medium findings.
- Whether findings are fixed, unfixed, or accepted by an approved exception.

Mark the security test `Fail` when critical or high findings exist without a documented exception. Medium findings are non-blocking but must be triaged in the report. Mark any finding `Waived` only when the operator explicitly accepts the risk and the waiver records the image, CVE, severity, reason, approver, and expiration date.

## Lifecycle And Isolation Tests

Run destructive lifecycle tests only with explicit operator approval and only after CloudBank sample data can be destroyed.

### Uninstall And Reinstall

1. Uninstall CloudBank using `CBV5-AGENT.md` cleanup steps.
2. Uninstall OBaaS using `AGENTS.md` cleanup or uninstall guidance for the selected installation type.
3. Verify the namespace is empty except for explicitly retained or approved resources.
4. Reinstall OBaaS into the same namespace using the same values.
5. Rerun platform and CloudBank smoke tests, plus `7-test_all_services.sh` when the validation tier is `Full Validation`.

### Multi-OBaaS

Install a second OBaaS instance in a different namespace using the multi-tenant guidance and values policy in `AGENTS.md`.

Expected:

- Each OBaaS release is healthy.
- Each Eureka instance shows only services from its namespace.
- Each SigNoz instance shows only telemetry from its namespace.
- Ingress-nginx class names, controller values, and election IDs are unique when deprecated ingress-nginx is explicitly enabled for both tenants.
- When Coherence is enabled in either tenant, each release owns a uniquely named Coherence CR in its application namespace.

### BYODB

Run only when an external non-Autonomous Oracle Database is available and the privileged user has required grantable privileges.

Expected:

- `database.type: OTHER` values are used.
- DSN or host, port, and service name are correct.
- Privileged secret exists.
- Required `SELECT WITH GRANT OPTION` and `EXECUTE WITH GRANT OPTION` privileges are verified.
- OBaaS installs and CloudBank smoke tests pass.

## Failure Evidence

When any test fails, collect the relevant diagnostics from `AGENTS.md`, `CBV5-AGENT.md`, and the local platform docs, then attach them to the report. At minimum, evidence should cover:

- Current namespace workload state.
- Relevant Helm release status.
- Current and previous logs for failing pods.
- `describe` output for failing pods, jobs, PVCs, services, ingress, Gateway API resources, or other implicated resources.
- Namespace events sorted by time.
- Failed job logs, especially database initialization jobs.
- For MicroTx Workflow Server failures, collect workflow server health output, workflow server logs, service/endpoints output, Helm values, latest `obaas-run-sql-*` job logs, and application-user privilege or quota diagnostics for Flyway DDL failures such as `ORA-01031`.
- Gateway route, APISIX Admin API, and `apisix-plugin-metadata` sidecar output for route, auth, gateway, or APISIX telemetry failures.
- For Eureka/APISIX discovery failures, capture effective Helm values plus rendered and running APISIX ConfigMap discovery hosts.
- For Coherence failures, capture the Coherence CR, operator logs, requested member pods, CRD status, and namespace watch configuration.
- HTTP request and response evidence for endpoint failures.
- SigNoz, ClickHouse, OpenTelemetry collector, instrumentation, and application telemetry configuration evidence for observability failures.
- Browser automation error details for UI or screenshot failures.

## Run Report Template

Create one report per run at:

```text
<evidence-dir>/TEST-RUN-REPORT.md
```

Use this template:

```markdown
# OBaaS And CloudBank Test Run Report

## Run Metadata

| Field | Value |
| --- | --- |
| Run ID |  |
| Start Time |  |
| End Time |  |
| Tester / Agent |  |
| Repository Commit |  |
| Kubernetes Context |  |
| Cluster Type |  |
| Validation Tier | Full Validation / Local Functional |
| Platform Namespace |  |
| Prereqs Release |  |
| Application Namespace |  |
| OBaaS Release |  |
| OBaaS Chart Version |  |
| OBaaS App Version |  |
| Database Type |  |
| Access Path |  |
| Eureka Replicas |  |
| Coherence Enabled / Cluster Name / Persistence |  |
| CloudBank DB Name |  |
| CloudBank Image Tag |  |
| CloudBank Customer Implementation | `customer` / `customer-helidon` |
| Kafka Load Workload | `helidon-producer` / `helidon-consumer` / other / not enabled |
| OTMM Coordinator Enabled | true / false |
| OTMM Workflow Server Enabled | true / false |
| OTMM Console Requested / Effective | true / false |
| Evidence Directory |  |

## Executive Summary

Overall Status: Pass / Fail

Traffic-Light Rating: Green / Amber / Red

Pass Rate: `<passed>/<executed>` (`<percent>%`)

Summary:

- 

Rating rules:

- Green: all required tests pass, no unwaived critical/high image findings, no required evidence missing.
- Amber: only waived, local-capacity, optional-component, or non-blocking evidence issues remain.
- Red: any required install, platform, CloudBank, observability, isolation, or security test fails.

## Environment Summary

Cluster capacity:

- 

Storage:

- 

Network and access:

- 

Known deviations or waivers:

- 

## Test Results

| ID | Category | Status | Expected | Actual | Evidence | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| PRE-001 | Preflight |  |  |  |  |  |
| PRE-002 | Preflight |  |  |  |  |  |
| PRE-003 | Preflight |  |  |  |  |  |
| PRE-004 | Preflight |  |  |  |  |  |
| PRE-005 | Preflight |  |  |  |  |  |
| PRE-006 | Preflight |  |  |  |  |  |
| PRE-007 | Preflight |  |  |  |  |  |
| PRE-008 | Preflight |  |  |  |  |  |
| INST-001 | Install |  |  |  |  |  |
| INST-002 | Install |  |  |  |  |  |
| INST-003 | Install |  |  |  |  |  |
| INST-004 | Install |  |  |  |  |  |
| PLAT-001 | Platform |  |  |  |  |  |
| PLAT-002 | Platform |  |  |  |  |  |
| PLAT-003 | Platform |  |  |  |  |  |
| PLAT-004 | Platform |  |  |  |  |  |
| PLAT-005 | Platform |  |  |  |  |  |
| PLAT-006 | Platform |  |  |  |  |  |
| PLAT-007 | Platform |  |  |  |  |  |
| PLAT-008 | Platform |  |  |  |  |  |
| PLAT-009 | Platform |  |  |  |  |  |
| PLAT-010 | Platform |  |  |  |  |  |
| PLAT-011 | Platform |  |  |  |  |  |
| PLAT-012 | Platform |  |  |  |  |  |
| PLAT-013 | Platform |  |  |  |  |  |
| PLAT-014 | Platform |  |  |  |  |  |
| CB-001 | CloudBank |  |  |  |  |  |
| CB-002 | CloudBank |  |  |  |  |  |
| CB-003 | CloudBank |  |  |  |  |  |
| CB-004 | CloudBank |  |  |  |  |  |
| CB-005 | CloudBank |  |  |  |  |  |
| CB-006 | CloudBank |  |  |  |  |  |
| CB-007 | CloudBank |  |  |  |  |  |
| CB-008 | CloudBank |  |  |  |  |  |
| CB-009 | CloudBank |  |  |  |  |  |
| CB-010 | CloudBank |  |  |  |  |  |
| CB-011 | CloudBank |  |  |  |  |  |
| CB-012 | CloudBank |  |  |  |  |  |
| CB-013 | CloudBank |  |  |  |  |  |
| CB-014 | CloudBank |  |  |  |  |  |
| OBS-001 | Observability |  |  |  |  |  |
| OBS-002 | Observability |  |  |  |  |  |
| OBS-003 | Observability |  |  |  |  |  |
| OBS-004 | Observability |  |  |  |  |  |
| OBS-005 | Observability |  |  |  |  |  |
| OBS-006 | Observability |  |  |  |  |  |
| OBS-007 | Observability |  |  |  |  |  |
| OBS-008 | Observability |  |  |  |  |  |
| OBS-009 | Observability |  |  |  |  |  |
| OBS-010 | Observability |  |  |  |  |  |
| OBS-011 | Observability |  |  |  |  |  |
| OBS-012 | Observability |  |  |  |  |  |
| OBS-013 | Observability |  |  |  |  |  |
| OBS-014 | Observability |  |  |  |  |  |
| OBS-015 | Observability |  |  |  |  |  |
| OBS-016 | Observability |  |  |  |  |  |
| OBS-017 | Observability |  |  |  |  |  |
| SEC-001 | Security |  |  |  |  |  |
| SEC-002 | Security |  |  |  |  |  |
| SEC-003 | Security |  |  |  |  |  |
| LIFE-001 | Lifecycle |  |  |  |  |  |
| LIFE-002 | Lifecycle |  |  |  |  |  |
| MT-001 | Multi-OBaaS |  |  |  |  |  |
| MT-002 | Multi-OBaaS |  |  |  |  |  |
| MT-003 | Multi-OBaaS |  |  |  |  |  |
| DB-001 | BYODB |  |  |  |  |  |

## Platform Evidence Summary

| Component | Status | Evidence | Notes |
| --- | --- | --- | --- |
| APISIX Gateway Service |  |  |  |
| APISIX Admin API Routes |  |  |  |
| APISIX OpenTelemetry Runtime Metadata |  |  |  |
| Eureka UI/API |  |  |  |
| Eureka/APISIX Replica Alignment |  |  |  |
| Config Server |  |  |  |
| Spring Boot Admin UI |  |  |  |
| Oracle Database Exporter |  |  |  |
| OTMM/MicroTx Runtime |  |  | Optional; required only when `otmm.coordinator.enabled=true`; include version-specific known failures instead of omitting this row. |
| MicroTx Transfer Workflow |  |  | Optional; required only when `otmm.coordinator.enabled=true`; include CloudBank transfer evidence and failure diagnostics when failing. |
| MicroTx Workflow Server |  |  | Optional; required only when `otmm.workflowServer.enabled=true`; include deployment, pod, service, endpoint, and health evidence. |
| Workflow Server Flyway DB Initialization |  |  | Optional; required only when workflow server is enabled; include migration logs and any Oracle privilege diagnostics. |
| OTMM Console |  |  | Optional; required only when `otmm.console.enabled=true` and either coordinator or workflow server is enabled; verify `/consoleui/`, not service root `/`; do not use as workflow server evidence. |
| Coherence Cluster |  |  | Optional and deprecated; when enabled, include operator/CRD, CR, member-count, namespace-watch, and persistence evidence. |

## Observability Evidence Summary

Telemetry readiness summary:

- Readiness check time window:
- Direct telemetry evidence:
- Load generated before capture: Yes / No
- Load evidence:
- Ingestion wait time:
- Screenshot validation evidence:
- Collector scrape health evidence:

| View / Dashboard | Telemetry Data Present Before Capture | Screenshot Validation | Status | Evidence | Notes |
| --- | --- | --- | --- | --- | --- |
| SigNoz Services |  |  |  |  |  |
| Services P99/Error Rate/OPS Columns |  |  |  |  |  |
| Traces |  |  |  |  |  |
| Logs |  |  |  |  |  |
| Metrics |  |  |  |  |  |
| Infra Monitoring |  |  |  |  |  |
| Dashboards List |  |  |  |  |  |
| Spring Boot Observability |  |  |  |  |  |
| Spring Boot Statistics |  |  |  |  |  |
| Oracle Database Dashboard |  |  |  |  |  |
| APISIX Dashboard |  |  |  |  | Gateway/service health belongs in Platform Evidence Summary; this row is for SigNoz APISIX observability. |
| HTTP API Monitoring |  |  |  |  |  |
| DB Calls Monitoring |  |  |  |  |  |
| JVM Metrics |  |  |  |  |  |
| MicroTx |  |  |  |  | Optional; if `otmm.coordinator.enabled=true`, record coordinator/LRA evidence and workflow-server telemetry when workflow server is enabled. If disabled, mark `Not Applicable` with values evidence. |
| Kafka Server Monitoring Dashboard |  |  |  |  |  |
| Helidon Main Dashboard |  |  |  |  |  |
| Helidon MP Details |  |  |  |  |  |
| Helidon SE Details |  |  |  |  |  |
| Helidon JVM Details |  |  |  |  |  |
| Helidon JVM Peak Virtual Threads |  |  |  |  | Validate `Peak Active Virtual Threads` and `Peak Pinned Virtual Threads` as window maxima. |
| Collector Scrape Health |  |  |  |  | EndpointSlice discovery and no repeated self-scrape/deprecated-v1 warnings. |

## Security Scan Summary

| Image | Scanner | Digest | Critical | High | Medium | Low | Status | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |  |  |  |

Exceptions:

| Image | CVE | Severity | Reason | Approver | Expiration |
| --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |

Medium finding triage:

| Image | CVE | Reason / Disposition | Evidence |
| --- | --- | --- | --- |
|  |  |  |  |

## Failure Diagnostics

| Test ID | Symptom | Evidence | Likely Cause | Recommended Action |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |

## Sign-Off

| Role | Name | Date | Notes |
| --- | --- | --- | --- |
| Tester |  |  |  |
| Reviewer |  |  |  |
| Operator Approval For Waivers |  |  |  |
```

## Completion Criteria

A run is complete only when:

- The selected installation tier is explicitly recorded.
- Required install and platform tests are complete.
- CloudBank deployment and smoke tests are complete; `7-test_all_services.sh` is also complete for `Full Validation`.
- Observability readiness checks prove required telemetry existed before screenshots were captured, or load generation was run and the checks were repeated.
- Collector scrape health is verified, including EndpointSlice discovery and the absence of repeated collector self-scrape or deprecated-v1 warnings.
- Observability evidence includes SigNoz Services, traces, logs, metrics, dashboards, dashboard-population screenshots, load-generation output, and dashboard validation metadata that distinguishes populated, partial, empty, zero-only, and not-applicable dashboards.
- Screenshot validation guardrails pass for every required UI evidence file.
- Vulnerability scans are complete; medium findings are triaged, and critical/high findings are resolved or explicitly waived by the operator.
- Every failure has logs, events, command output, and a recommended next action.
- The run report contains an overall pass/fail result, pass rate, traffic-light rating, and evidence links.
