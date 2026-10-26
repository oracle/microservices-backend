# Policy Retrieval Service

`policy-retrieval-service` is the Spring Boot API that retrieves authorized
policy evidence from Oracle vector-backed policy chunks. It participates in
`cloudbank-loan-origination` version `1` through the
`policy_evidence_retrieval` MicroTx HTTP task.

The service is read-only. On OBaaS / OKE, the corpus is populated before this
Deployment starts by the one-shot `policy-loader`. Its loader-only deployment
delta is documented in
[`src/policy-loader/README.md`](../policy-loader/README.md); common OCI GenAI
and Workload Identity setup remains in the OBaaS services runbook.

## Port And Routing

The service listens on port `8086` by default. The full-demo Compose stack maps
port `8086` on the host to port `8086` in the container.

```text
Host:      http://127.0.0.1:8086
Container: http://policy-retrieval-service:8086
Minikube:  http://host.minikube.internal:8086
```

MicroTx uses the Minikube-to-host address because the local Workflow Server
runs in Minikube while Policy Retrieval runs in Compose. A Kubernetes deployment
should instead set `policyRetrievalBaseUrl` to the cluster-reachable Service
DNS.

## API

The workflow calls the service-to-service endpoint:

```text
GET /internal/api/v1/policy-evidence?query=loan%20underwriting%20income%20affordability
```

This endpoint requires an `azn-server` JWT with `aud=cloudbank-api`,
`token_kind=service`, scope `cloudbank.internal`, and an allow-listed
`client_id`. It fixes the maximum result count to `3`, the AI use to
`retrieval`, and the maximum policy visibility to `UNDERWRITER`; the shared
workflow service identity is not treated as a user and does not need a user
role claim.

The generic role-aware endpoint remains available for authenticated user
tokens:

```text
GET /policy?query=<query>&limit=3&aiUse=retrieval
```

It derives the maximum visible policy classification from the caller's
CloudBank policy role. The `aiUse` parameter uses the lowercase API values
declared by the service, including `retrieval`; Spring converts those values to
the corresponding domain enum.

Health is available without authentication:

```text
GET /actuator/health
```

## Local Compose Configuration

The service is enabled by the `full-demo` profile. OCI values are read only
from the repository-root `.env`; `run-compose.sh` does not inherit them from
the invoking shell. Fill at least:

```dotenv
POLICY_OCI_GENAI_AUTHENTICATION_TYPE=FILE
POLICY_OCI_GENAI_CONFIG_DIRECTORY=/absolute/path/to/oci/config-directory
POLICY_OCI_GENAI_PROFILE=DEFAULT
POLICY_OCI_GENAI_REGION=eu-frankfurt-1
POLICY_OCI_GENAI_EMBEDDING_MODEL=<embedding-model>
POLICY_OCI_GENAI_EMBEDDING_COMPARTMENT_ID=<compartment-ocid>
```

`POLICY_OCI_GENAI_REGION` identifies the OCI region in which Generative AI is
called; it does not by itself provide enough configuration to invoke the
embedding model. The region can be omitted from this variable only when the
selected OCI config profile already declares it. An explicit
service endpoint and custom embedding dimensions are not part of the local
`FILE`-authentication Compose contract.

The OCI directory must contain a file named `config` and its referenced private
key. The selected profile, `DEFAULT` in the example, must provide valid tenancy
OCID, user OCID, fingerprint, key-file reference, and region unless the region
is supplied separately above. The configured OCI principal must also have IAM
permission to use OCI Generative AI in
`POLICY_OCI_GENAI_EMBEDDING_COMPARTMENT_ID`, and the selected embedding model
must be available in the configured region.

Compose mounts only the configured OCI directory read-only. It does not read
OCI configuration from the invoking shell. Database access uses the dedicated
`CB_POLICY_APPLICATION_APP` account and the least-privilege
`CB_POLICY_RETRIEVAL_RUNTIME` role. Native JDBC queries qualify policy tables
with the owner schema configured by `POLICY_SCHEMA`, which defaults to
`CLOUDBANK`; the runtime account does not own those tables.

With `FILE` authentication, tenancy OCID, user OCID, fingerprint, private-key
path, and any key passphrase belong only in the selected OCI config profile.
`run-compose.sh` neither creates corresponding `.env` placeholders nor passes
those values individually to the container.

Start the stack with:

```bash
./run-compose.sh up
```

## Smoke Test

For a running full-demo Compose stack, use the repository command:

```bash
./run-compose.sh verify
```

It obtains a short-lived service token, confirms that anonymous workflow-policy
retrieval is rejected, and verifies that the protected policy-evidence endpoint
returns no more than its contract limit of three results. The smoke test is
read-only: it does not upload, seed, or change policy data.
