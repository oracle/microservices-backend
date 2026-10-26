# Deploy CloudBank AI services on OBaaS / OKE

This runbook deploys every CloudBank AI service except `azn-server`. Complete
[`azn-server-runbook.md`](azn-server-runbook.md) first: its Chapter 1 is the
single source for all operator-supplied deployment configuration in `.env`.

The deployment creates or upgrades eight internal application services, runs
the ADB schema bootstrap and policy-corpus loader, publishes private images to
OCIR, and waits for ready Deployments and EndpointSlices. It does not create
public gateway routes and does not publish the MicroTx workflow definition.

## Managed workloads

| Workload | Docker target | Kubernetes port | Database |
| --- | --- | ---: | --- |
| `loan-application-service` | `loan-application-service` | 8080 | yes |
| `document-ingest` | `document-ingest` | 8080 | yes |
| `document-review-service` | `document-review-service` | 8080 | yes |
| `decision-service` | `decision-service` | 8080 | yes |
| `ai-agent-service` | `ai-agent-service` | 8080 | yes |
| `geographic-risk-service` | `geographic-risk-service` | 8080 | yes |
| `policy-retrieval-service` | `policy-retrieval-service` | 8080 | yes |
| `workflow-token-refresh-worker` | `workflow-token-refresh-worker` | 8080 | no |
| ADB bootstrap Job | `cloudbank-schema-init` | n/a | privileged bootstrap |
| Lab owner access Job | `cloudbank-schema-init` | n/a | privileged bootstrap |
| Policy loader Job | `policy-loader` | n/a | dedicated write identity |

All application Services are `ClusterIP`. The Java processes use port 8080 in
OKE, matching `workflow-v1-obaas.json`.

## Prerequisites

- The installed OBaaS release has a semantic `appVersion` of 2.1.0 or later,
  with an `obaas-sample-app` chart advertising the same complete `appVersion`.
- `azn-server` was successfully installed with
  `./cloudbank-v6/deploy/obaas/deploy-azn-server_v1.sh first-deploy` and is healthy in the
  namespace configured by `MICROTX_NAMESPACE`.
- MicroTx authentication was enabled as documented in
  [`secure-microtx-azn.md`](secure-microtx-azn.md).
- The workstation provides OCI CLI, `kubectl`, Helm 3.8 or newer (including
  Helm 4), `jq`, OpenSSL, `patch`, Docker with Buildx, and Maven.
- OCI CLI authentication works for the target tenancy. The OCI identity may
  inspect the OKE cluster and create/read private OCIR repositories in
  `OCI_COMPARTMENT_OCID`.
- Docker can build for the OKE node architecture, obtain the base images used
  by the root `Dockerfile`, and publish to OCIR.
- The OCI IAM policies in [Step 2.2](#22-authorize-the-ai-workloads) exist and
  have propagated.

Do not run `run-compose.sh` manually for this deployment. The initial
`azn-server` procedure already initialized `.env`; the service helper packages
the versioned SQLcl and Liquibase assets and runs them directly against the ADB
provisioned with OBaaS.

## 0. Reuse the shared `.env` configuration

There is no additional value to export for Step 0. Chapter 1 of
[`azn-server-runbook.md`](azn-server-runbook.md#1-configure-env) already stores:

- the dedicated kubeconfig path, OCI region, OKE cluster OCID, OBaaS release,
  and namespace;
- the OCIR compartment, identity, authentication token, and image-pull Secret
  name;
- both Workload Identity ServiceAccount names, both OCI GenAI model IDs, and
  the OKE cluster compartment;
- the geographic-risk diagnostic selector, which normally remains `false`.

`deploy-services.sh` reads those values only from the repository-root `.env`.
It sets `KUBECONFIG` to `CLOUDBANK_KUBECONFIG_PATH`, derives the current
context from that dedicated file, and verifies that the configured OBaaS
release is in `MICROTX_NAMESPACE`. Do not source `.env`: it contains secrets.

The installed OBaaS privileged database Secret, wallet Secret, database service
alias, `azn-server` issuer, and internal MicroTx Workflow Server URL are live
cluster state, not operator configuration. The helper detects and validates
them without printing Secret values. It stops if any required target is absent
or ambiguous.

## 1. Move to the repository root

Run the commands below from the directory containing `.env`, `run-compose.sh`,
`Dockerfile`, and `pom.xml`:

```bash
cd /path/to/cloudbank-ai-obaas
```

Protect `.env` with mode `600` and never print, source, commit, or paste its
contents into a command, log, screenshot, or support request.

## 2. Prepare OKE Workload Identity for the AI services

`policy-retrieval-service` and `ai-agent-service` call OCI Generative AI through
OKE Workload Identity. Their Pods do not receive an OCI configuration file,
API key, user private key, or dynamic-group identity. The policy loader reuses
the policy-retrieval ServiceAccount, so it needs no additional IAM policy.

### 2.2 Authorize the AI workloads

Ask an IAM administrator to create these statements once in the compartment
identified by `OKE_CLUSTER_COMPARTMENT_ID`. Replace the placeholders with the
matching values already stored in `.env`:

```text
Allow any-user to use generative-ai-text-embedding in compartment id <oke-cluster-compartment-ocid> where all {
  request.principal.type = 'workload',
  request.principal.namespace = '<obaas-application-namespace>',
  request.principal.service_account = 'policy-retrieval-service',
  request.principal.cluster_id = '<oke-cluster-ocid>'
}
```

```text
Allow any-user to use generative-ai-chat in compartment id <oke-cluster-compartment-ocid> where all {
  request.principal.type = 'workload',
  request.principal.namespace = '<obaas-application-namespace>',
  request.principal.service_account = 'ai-agent-service',
  request.principal.cluster_id = '<oke-cluster-ocid>'
}
```

If `.env` uses non-default values for `POLICY_SERVICE_ACCOUNT` or
`AI_SERVICE_ACCOUNT`, substitute those exact names in the statements. The
namespace must equal `MICROTX_NAMESPACE`; the cluster and compartment values
must equal `OKE_CLUSTER_OCID` and `OKE_CLUSTER_COMPARTMENT_ID`. The selected
embedding and chat models must be on-demand models available in `OCI_REGION`.

OKE Workload Identity uses the `workload` principal directly. Do not create a
dynamic group and do not add an OCI key or config-file mount. See Oracle's
[Granting Workloads Access to OCI Resources](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contenggrantingworkloadaccesstoresources.htm).

## 3. OCIR credentials, image tag, and pull Secret

No shell export is required:

- `OCI_IDENTITY_NAME`, `OCI_COMPARTMENT_OCID`, and `OCI_AUTH_TOKEN` come from
  `.env`. The token is passed to `docker login` through standard input and is
  never displayed.
- `IMAGE_PULL_SECRET` comes from `.env`. The documented
  `cloudbank-ai-ocir-pull` name is safe for separate OBaaS installations in
  different namespaces because Kubernetes Secret names are namespace-scoped.
  In the same namespace, an existing Secret with that name must be type
  `kubernetes.io/dockerconfigjson`; otherwise the helper stops. On each deployment,
  the helper refreshes credentials from `OCI_IDENTITY_NAME` and `OCI_AUTH_TOKEN`,
  embedding authentication for Kubernetes without relying on Docker Desktop's
  host credential helper. Dry-run does not update the Secret.
- A new immutable `oke-<UTC timestamp>` image tag is generated automatically
  for every `first-deploy` or `redeploy`. Do not set `IMAGE_TAG` or
  `NEW_IMAGE_TAG` for this script.

The helper creates the ten private `cloudbank-ai/<target>` repositories when
missing: eight service repositories plus `cloudbank-schema-init` and
`policy-loader`.

## 4. First deployment

Run one command:

```bash
cd ./cloudbank-v6
./deploy/obaas/deploy-services.sh first-deploy
```

Before any mutation, the command:

1. validates `.env`, kubeconfig access, the OKE cluster/compartment boundary,
   the exact OBaaS release/namespace, `azn-server`, platform database and
   wallet Secrets, and the MicroTx Service; it also verifies the exact
   `obaas-admin` identity and issuer using the existing admin credential in `.env`;
2. discovers the node architecture and a version-compatible
   `obaas-sample-app` chart;
3. renders and lints every manifest and submits non-persistent Kubernetes
   server-side dry runs;
4. displays the resolved deployment plan without passwords, tokens, private
   keys, or Secret contents.

Review the plan. The displayed namespace and release must match
`MICROTX_NAMESPACE` and `OBAAS_RELEASE` in `.env`. Answer `y` only when the
target is correct. There is no separate dry-run command and no need to export
the namespace shown in the plan.

After confirmation, the helper runs the root Maven test suite, authenticates to
OCIR, creates missing private repositories and the namespaced pull Secret,
builds and publishes all ten images, and performs these ordered operations:

1. create only missing schema-owner and least-privilege database Secrets;
2. run the restart-safe `cloudbank-schema-init` Job against ADB;
3. provision and verify `obaas-admin` access to all current and future loan
   applications using its persistent authorization-server principal ID;
4. create/validate the policy ServiceAccount and run the idempotent policy
   loader with OCI GenAI embeddings;
5. install the eight Helm releases in dependency order;
6. wait for every Deployment rollout and ready EndpointSlice.

Existing credentials are validated but not rotated or replaced. The schema
initializer and temporary lab-owner bootstrap Jobs read the privileged OBaaS
database Secret. Database-less
services receive neither the wallet nor a runtime database Secret.

The lab has one interactive profile, `obaas-admin`. Its application access is
verified on both first deployment and redeploy, preserving the backend grant
model for future restricted users. See the [lab owner runbook](lab-owner-runbook.md)
for existing-installation repair and authorization guard behavior.

## 4.1 Enable Geocoding on ADB. 

From OCI Web console add your IP address to the `Access control list` to use the SQL ADB console. As admin from OCI Web console:

```sql
EXEC SDO_GCDR.ELOC_GRANT_ACCESS('CB_GEOGRAPHIC_RISK_APP');
```



## 5. Verify the deployment

Successful completion already means that every rollout and EndpointSlice
check passed. For an additional non-sensitive inspection, read only the needed
selectors from `.env` without sourcing it:

```bash
env_value() {
  awk -F= -v name="$1" '$1 == name { print substr($0, index($0, "=") + 1) }' .env
}

KUBECONFIG_PATH="$(env_value CLOUDBANK_KUBECONFIG_PATH)"
NAMESPACE="$(env_value MICROTX_NAMESPACE)"
POLICY_ACCOUNT="$(env_value POLICY_SERVICE_ACCOUNT)"
AI_ACCOUNT="$(env_value AI_SERVICE_ACCOUNT)"
CONTEXT="$(KUBECONFIG="$KUBECONFIG_PATH" kubectl config current-context)"

KUBECONFIG="$KUBECONFIG_PATH" kubectl --context "$CONTEXT" -n "$NAMESPACE" \
  get deployments \
  loan-application-service document-ingest document-review-service \
  decision-service ai-agent-service geographic-risk-service \
  policy-retrieval-service workflow-token-refresh-worker \
  -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas

KUBECONFIG="$KUBECONFIG_PATH" kubectl --context "$CONTEXT" -n "$NAMESPACE" \
  get serviceaccount "$POLICY_ACCOUNT" "$AI_ACCOUNT"

KUBECONFIG="$KUBECONFIG_PATH" kubectl --context "$CONTEXT" -n "$NAMESPACE" \
  get deployment policy-retrieval-service ai-agent-service \
  -o custom-columns=NAME:.metadata.name,SERVICE_ACCOUNT:.spec.template.spec.serviceAccountName
```

The two Deployments must show the ServiceAccount names stored in `.env`, never
`default` or an empty value. Completed bootstrap Jobs have a one-hour TTL and
may already have been garbage-collected.

For an HTTP readiness check, port-forward one internal Service temporarily and
query only its public health endpoint. Spring services expose
`/actuator/health`; `geographic-risk-service` exposes `/health/ready`. Do not
print customer data, authorization headers, cookies, workflow input, extracted
text, or OCI configuration.

## 6. Redeploy

After application changes, run:

```bash
cd ./cloudbank-v6
./deploy/obaas/deploy-services.sh redeploy
```

The command generates a new immutable image tag, repeats the integrated
preflight, displays the plan, asks for confirmation, rebuilds all ten targets,
applies pending idempotent schema changes, verifies or loads the policy corpus,
and waits for all service rollouts.

`redeploy` upgrades a service that has both its Helm release and Deployment and
installs a newly introduced service when neither exists. It rejects an
inconsistent state in which only one of those resources exists. It does not
rotate existing database, OAuth, or signing-key Secrets. It refreshes the
image-pull Secret using the current OCIR credentials from `.env`.

The deployment plan displays the Helm conflict mode. When the installed Helm
supports server-side apply and `--force-conflicts`, upgrades use
`--server-side=true --force-conflicts`, matching the manifest preflight. The
generated chart values take ownership of chart-rendered fields previously
edited by tools such as `kubectl set env`. This includes `AZN_ISSUER_URI`.
Helm 3 receives no unsupported flags. The same policy applies to first
deployment, recovery of an interrupted deployment, Azn, and the BFF.

## 7. Stop conditions and recovery

- A missing or ambiguous platform Secret, unreachable MicroTx Service, or
  mismatched OBaaS target stops the integrated preflight. An invalid pull
  Secret or public OCIR repository stops execution before image publication.
- A Maven, build, or push failure does not modify application Deployments.
- A failed schema Job preserves the generated database Secrets. Correct the
  cause and rerun the same deployment mode; a new immutable tag and Job name
  are generated. Do not delete or regenerate the database Secrets.
- A failed policy load never authorizes automatic table or Secret deletion.
  Follow [`src/policy-loader/README.md`](../../src/policy-loader/README.md).
- If an older helper stopped on a Helm ownership conflict after bootstrap and
  policy loading, rerun the updated helper in the same mode. Bootstrap and
  policy loading are restart-safe; the command repeats the build/push stages
  and retries the failed Helm release without resetting the database.
- If `first-deploy` was interrupted after creating only some releases, rerun
  `first-deploy`. The helper accepts its own compatible partial installation,
  reconciles the existing services with the newly generated tag, and installs
  the remainder.
- Do not begin troubleshooting with `helm uninstall`, namespace/PVC deletion,
  or `kubectl delete secret`. First inspect redacted Helm, Deployment, Pod, Job,
  EndpointSlice, and event status.

The script always requires an interactive confirmation after its preflight; it
must not be started automatically merely because documentation was generated.

## Document-summary runtime

`ai-agent-service` now requires its own `CB_AI_AGENT_APP` database identity and
wallet mount. The deployment helper provisions its dedicated database Secret,
applies schema changes 029/030 through the shared initializer, and supplies
`AI_DATASOURCE_*`, `AI_SCHEMA`, and `DOCUMENT_INGEST_BASE_URL`. Its database role
has SELECT/INSERT on `CB_AI_DOCUMENT_SUMMARY` only. Evidence access still uses
OAuth service APIs, with `DOCUMENT_INGEST_REVIEW_INPUT_CLIENT_IDS` granting the
AI identity access to the bounded projection without permitting extraction or
PDF diagnostics. OCI credentials, service tokens, and wallet material remain
outside workflow definitions and result payloads.

Before using the new path, redeploy ingest and the AI service with the schema
migration, then validate and publish the updated workflow definition through
the existing workflow deployment helper. Test a completed synthetic review in
OKE for `oci-genai` output and durable replay; test unavailable model output for
`AI_DOCUMENT_SUMMARY_UNAVAILABLE`, continued APPROVED/REJECTED routing without an
additional human gate, and availability information on the existing
MANUAL_REVIEW task.
The default component smoke tests verify authorization and missing-evidence
handling without invoking OCI.
