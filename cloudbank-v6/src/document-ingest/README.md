# CloudBank Document Ingest Service

`document-ingest` is the CloudBank workflow worker that converts authorized PDF content into structured JSON. It retrieves uploaded documents from `loan-application-service`, verifies their integrity, persists idempotent extraction results in Oracle Database, and acknowledges document status back to the owning service.

It does not own application intake, uploaded-file storage, document review, workflow orchestration, loan decisions, or AI tasks. The local extraction provider uses Apache PDFBox and deterministic parsing. A production provider such as OCI Document Understanding can replace it without changing the workflow-facing API.

Application association comes from the authenticated workflow request, the loan
manifest and persisted application/document keys. The parser never searches PDF
text for an application ID. A manifest for another application fails before
content retrieval/persistence. The legacy diagnostic packet `applicationId` and
review fact `applicationIdFromDocument` remain null; the workflow/review envelope
still carries the canonical intake ID. Ready PDFs and the shared GUI/CLI intake
template are in `synthetic_data/customer_packets/demo_geocoded_loan/`.

## Contents

- [Quick start](#quick-start)
- [Responsibilities and boundaries](#responsibilities-and-boundaries)
- [Security boundary](#security-boundary)
- [Extraction workflow](#extraction-workflow)
- [API](#api)
- [Request and response contracts](#request-and-response-contracts)
- [API examples](#api-examples)
- [Extraction behavior and idempotency](#extraction-behavior-and-idempotency)
- [Failure behavior](#failure-behavior)
- [Configuration](#configuration)
- [Operational endpoints](#operational-endpoints)
- [Local startup](#local-startup)
- [Running instance smoke test](#running-instance-smoke-test)
- [Build and test](#build-and-test)
- [Troubleshooting](#troubleshooting)

## Quick start

From the repository root, start the complete local stack and run its authenticated component checks:

```bash
./run-compose.sh up
./run-compose.sh verify
```

Verify the document-ingest service directly:

```bash
curl --fail-with-body http://127.0.0.1:8082/actuator/health
```

The default service URL is `http://127.0.0.1:8082`. The repository workflow starts Oracle, provisions both runtime accounts, starts `azn-server` and `loan-application-service`, then starts document ingest. `verify` obtains its own short-lived tokens; no token needs to be copied into the terminal.

See [API examples](#api-examples) for development-time requests with an existing service token and the [root README](../../README.md) for stack lifecycle, schema profiles, reset, and purge behavior.

## Responsibilities and boundaries

The service owns:

- deterministic PDF text extraction and field parsing;
- direct diagnostic extraction of PDF, ZIP, and multipart inputs;
- workflow-managed document retrieval and integrity verification;
- idempotent persistence in `CLOUDBANK.CB_DOCUMENT_EXTRACTION`;
- document extraction status acknowledgement;
- safe application, workflow, task, document, and trace correlation.

The service does not own:

- application or document metadata creation;
- PDF BLOB storage or direct database access to uploaded content;
- document completeness review or manual-review routing;
- workflow state or cross-service orchestration;
- policy, risk, approval, rejection, or adverse-action decisions;
- AI summarization, reviewer assistance, or explanation generation.

`loan-application-service` remains the system of record for uploaded PDF content and canonical document status. MicroTx Workflows coordinates when document extraction runs.

## Security boundary

Every extraction endpoint is internal. Callers must present a JWT issued by `azn-server` containing:

- the configured `iss` value;
- `aud=cloudbank-api`;
- `scope` containing `cloudbank.internal`;
- `token_kind=service`;
- a `client_id` included in `DOCUMENT_INGEST_CALLER_CLIENT_IDS`.

Document ingest uses a separate outbound client-credentials identity, normally `cloudbank-document-ingest-client`, when calling the loan service. The inbound CloudBank workflow-task token is never forwarded downstream and must not be confused with the dedicated MicroTx Workflow API token.

`CB_DOCUMENT_INGEST_APP` receives only `CB_DOCUMENT_INGEST_RUNTIME`. It can persist extraction rows and access permitted metadata, but it cannot read PDF BLOBs directly. PDF retrieval always goes through the authenticated loan-service API so ownership, authorization, and audit remain at the owning boundary.

Browser and UI code must not call this service directly or store bearer tokens, client secrets, database credentials, signing material, or raw extraction credentials. Any future browser-facing extraction view belongs behind the BFF boundary.

## Extraction workflow

MicroTx invokes `POST /internal/api/v1/document-extractions` with correlation data rather than PDF bytes. For each processable document, the worker:

1. obtains its own `cloudbank-document-ingest-client` client-credentials token from `azn-server`;
2. retrieves the authorized document manifest from `loan-application-service`;
3. retrieves each authorized PDF through the loan-service content API;
4. verifies byte length and SHA-256 against the manifest;
5. extracts deterministic structured JSON;
6. persists an idempotent extraction row through `CB_DOCUMENT_INGEST_APP`;
7. acknowledges `RECEIVED` as `EXTRACTED`, or records a bounded failure status;
8. returns document and extraction identifiers with the structured result.

No PDF bytes, database credentials, signed URLs, user tokens, client secrets, or private keys pass through the workflow payload.

See [Loan document intake and extraction](../../docs/architecture/loan-document-intake-and-extraction.md) for the complete developer-facing sequence from application creation and SecureFiles upload through authenticated retrieval, JSON persistence, and status acknowledgement.

## API

All extraction routes require the internal service JWT described above. They are not public or browser-facing APIs.

| Method and endpoint | Success | Input | Purpose |
| --- | --- | --- | --- |
| `POST /internal/api/v1/document-extractions` | `200` | JSON and `Idempotency-Key` | Run the complete workflow-managed retrieval, verification, extraction, persistence, and acknowledgement path. |
| `POST /internal/api/v1/diagnostic-extractions/pdf-documents` | `200` | `application/pdf` | Directly extract one uploaded PDF without loan-service retrieval or persistence. |
| `POST /internal/api/v1/diagnostic-extractions/zip-archives` | `200` | `application/zip` | Directly extract PDF entries from a ZIP archive. |
| `POST /internal/api/v1/diagnostic-extractions/file-batches` | `200` | `multipart/form-data` with one or more `files` parts | Directly extract uploaded PDF files and expand uploaded ZIP files. |

The diagnostic routes exist for deterministic component testing and trusted backend diagnostics. Workflow integrations must use `/internal/api/v1/document-extractions`.

## Request and response contracts

### Workflow extraction request

```http
POST /internal/api/v1/document-extractions
Authorization: Bearer <allow-listed-service-token>
Idempotency-Key: extract:APP-EXAMPLE:workflow-001
Content-Type: application/json
```

```json
{
  "applicationId": "APP-EXAMPLE",
  "workflowId": "workflow-001",
  "taskReference": "extract-documents",
  "traceId": "0123456789abcdef0123456789abcdef"
}
```

| Field | Constraint |
| --- | --- |
| `Idempotency-Key` | 8–200 letters, numbers, `.`, `_`, `:`, or `-`. |
| `applicationId` | Required; maximum 80 characters. |
| `workflowId` | Required; maximum 100 characters. |
| `taskReference` | Required; maximum 120 characters. |
| `traceId` | Exactly 32 hexadecimal characters. |

### Workflow extraction response

The response correlates every persisted extraction to its application, workflow, task, and source document:

```json
{
  "applicationId": "APP-EXAMPLE",
  "workflowId": "workflow-001",
  "taskReference": "extract-documents",
  "results": [
    {
      "documentId": "DOC-EXAMPLE",
      "extractionId": "EXT-DOC-EXAMPLE-0123456789abcdef",
      "extraction": {
        "service": "cloudbank-document-ingest",
        "provider": "local_pdf_text",
        "packetCount": 1,
        "packets": [
          {
            "packetId": "upload",
            "documents": [
              {
                "fileName": "loan_application.pdf",
                "documentType": "LOAN_APPLICATION",
                "textLineCount": 42
              }
            ]
          }
        ]
      }
    }
  ]
}
```

The packet above is a shortened excerpt. A successful real response also contains applicant, employment, income, requested loan, liability, identity, banking, validation-signal, and warning fields populated from the source PDFs.

### Diagnostic extraction response

All three diagnostic routes return the same extraction envelope:

```json
{
  "service": "cloudbank-document-ingest",
  "provider": "local_pdf_text",
  "packetCount": 1,
  "packets": [
    {
      "packetId": "upload",
      "documents": [
        {
          "fileName": "loan_application.pdf",
          "documentType": "LOAN_APPLICATION",
          "textLineCount": 42
        }
      ],
      "validationSignals": [],
      "warnings": []
    }
  ]
}
```

This is a representative excerpt; the actual packet includes the other structured sections populated from the supplied documents.

## API examples

These examples are for trusted backend development against a running local service. Use only synthetic files and short-lived tokens. Never commit or paste real tokens, credentials, customer documents, private keys, or signing material into scripts, documentation, shell history, logs, or screenshots.

```bash
export INGEST_BASE_URL='http://127.0.0.1:8082'
export SERVICE_ACCESS_TOKEN='<short-lived-allow-listed-service-token>'
```

The component smoke test is the preferred way to obtain and use a service token without displaying it.

### Run a workflow-managed extraction

```bash
curl --fail-with-body \
  --request POST \
  --url "$INGEST_BASE_URL/internal/api/v1/document-extractions" \
  --header "Authorization: Bearer $SERVICE_ACCESS_TOKEN" \
  --header 'Content-Type: application/json' \
  --header 'Idempotency-Key: extract:APP-EXAMPLE:workflow-001' \
  --data @- <<'JSON'
{
  "applicationId": "APP-EXAMPLE",
  "workflowId": "workflow-001",
  "taskReference": "extract-documents",
  "traceId": "0123456789abcdef0123456789abcdef"
}
JSON
```

This request requires a real application with at least one processable document in the loan service. For a self-contained parser check, use one of the diagnostic routes instead.

### Extract one PDF directly

```bash
export PDF_PATH='synthetic_data/customer_packets/app_apr_001_elena_parker/loan_application.pdf'

curl --fail-with-body \
  --request POST \
  --url "$INGEST_BASE_URL/internal/api/v1/diagnostic-extractions/pdf-documents" \
  --header "Authorization: Bearer $SERVICE_ACCESS_TOKEN" \
  --header 'Content-Type: application/pdf' \
  --data-binary "@$PDF_PATH"
```

### Extract a ZIP archive

```bash
export ZIP_PATH='<path-to-synthetic-pdf-archive.zip>'

curl --fail-with-body \
  --request POST \
  --url "$INGEST_BASE_URL/internal/api/v1/diagnostic-extractions/zip-archives" \
  --header "Authorization: Bearer $SERVICE_ACCESS_TOKEN" \
  --header 'Content-Type: application/zip' \
  --data-binary "@$ZIP_PATH"
```

### Extract a multipart file batch

```bash
export PACKET_ROOT='synthetic_data/customer_packets/app_apr_001_elena_parker'

curl --fail-with-body \
  --request POST \
  --url "$INGEST_BASE_URL/internal/api/v1/diagnostic-extractions/file-batches" \
  --header "Authorization: Bearer $SERVICE_ACCESS_TOKEN" \
  --form "files=@$PACKET_ROOT/loan_application.pdf;type=application/pdf" \
  --form "files=@$PACKET_ROOT/pay_statement_novereign_systems.pdf;type=application/pdf" \
  --form "files=@$PACKET_ROOT/liability_schedule.pdf;type=application/pdf"
```

## Extraction behavior and idempotency

### Diagnostic grouping

- A single directly uploaded PDF is assigned to packet `upload` and the internal filename `upload.pdf`.
- ZIP entries are processed only when their names end in `.pdf`, case-insensitively.
- The first directory component of a ZIP entry becomes its packet ID. Files without a directory are grouped under `upload`.
- Multipart files ending in `.zip` are expanded using the same ZIP behavior.
- Other multipart filenames are treated as source documents. Non-PDF documents are skipped during extraction.
- Source documents are sorted by filename before parsing so field application is deterministic.

### Workflow idempotency

- The workflow handler requires a stable task-level `Idempotency-Key`.
- Extraction IDs are deterministic: `EXT-<documentId>-<first-16-SHA256-characters>`.
- Oracle persistence uses `MERGE`, so retrying the same document and content digest does not create a duplicate extraction row.
- Status callback event IDs are deterministic hashes of the task key, document ID, and target status.
- A document already marked `EXTRACTED` is not transitioned again.

The workflow response may be safely retried after a transport interruption as long as the caller reuses the same application, workflow task, source content, and idempotency key.

## Failure behavior

The workflow path distinguishes permanent integrity failures from retryable extraction failures:

- A byte-length or SHA-256 mismatch is acknowledged as `FAILED_FINAL` with reason `DOCUMENT_INTEGRITY_CHECK_FAILED`.
- An I/O, parsing, persistence, or other runtime failure is acknowledged as `FAILED_RETRYABLE` with reason `DOCUMENT_EXTRACTION_FAILED_RETRYABLE`.
- If the failure callback also fails, that callback exception is retained as a suppressed cause while the original extraction failure remains primary.
- An empty or missing processable manifest fails the workflow task before extraction begins.

Authentication failures return `401`; authenticated callers that fail the internal service-token policy return `403`. Unsupported request media types, invalid workflow fields, malformed PDFs or ZIPs, downstream loan-service failures, and database failures are rejected by the current Spring and service exception handling.

Current limitation: document ingest does not yet define the stable CloudBank JSON error envelope used by `loan-application-service`, and it does not define application-level PDF, archive, entry-count, expanded-archive, or multipart-total size limits. Callers must not depend on a stable error body, and deployed environments should enforce conservative gateway/container request limits until those policies are implemented in the service.

## Configuration

Application defaults are shown below. Database passwords, OAuth client secrets, tokens, and signing material must come from silent prompts, environment variables, or the deployment secret facility and must never be committed or logged.

### Database and HTTP

| Variable | Default | Required when | Purpose |
| --- | --- | --- | --- |
| `PORT` | `8082` | Optional | HTTP port. |
| `DOCUMENT_INGEST_DATASOURCE_URL` | `jdbc:oracle:thin:@//localhost:1521/freepdb1` | Override outside the local database | Oracle JDBC URL. |
| `DOCUMENT_INGEST_DATASOURCE_USERNAME` | `CB_DOCUMENT_INGEST_APP` | Optional | Least-privilege runtime account. |
| `DOCUMENT_INGEST_DATASOURCE_PASSWORD` | None | Always | Runtime database password; secret. |
| `DOCUMENT_INGEST_SCHEMA` | `CLOUDBANK` | Optional | Schema used to qualify extraction tables. |

### Inbound authorization

| Variable | Default | Required when | Purpose |
| --- | --- | --- | --- |
| `AZN_ISSUER_URI` | `http://127.0.0.1:8080` | Override outside local development | Required JWT issuer. |
| `AZN_JWK_SET_URI` | `http://127.0.0.1:8080/oauth2/jwks` | Override outside local development | JWT signing-key endpoint. |
| `AZN_AUDIENCE` | `cloudbank-api` | Optional | Required JWT audience. |
| `DOCUMENT_INGEST_CALLER_CLIENT_IDS` | `cloudbank-service-client` | Override for deployed workflow clients | Allow-list for inbound internal callers. |

### Loan-service client

| Variable | Default | Required when | Purpose |
| --- | --- | --- | --- |
| `DOCUMENT_INGEST_TOKEN_URI` | `http://127.0.0.1:8080/oauth2/token` | Override outside local development | Client-credentials token endpoint. |
| `DOCUMENT_INGEST_CLIENT_ID` | `cloudbank-document-ingest-client` | Optional | Outbound loan-service client ID. |
| `DOCUMENT_INGEST_CLIENT_SECRET` | None | Workflow extraction and local runner | Outbound OAuth client secret. |
| `LOAN_APPLICATION_BASE_URL` | `http://127.0.0.1:8081` | Override outside local development | Loan-service base URL. |

Spring virtual threads are enabled. Oracle UCP bounds database concurrency with an initial and minimum pool size of 1 and a maximum pool size of 4.

## Operational endpoints

| Endpoint | Access | Purpose |
| --- | --- | --- |
| `GET /health` | Public | Legacy compatibility response containing `status` and `service`. |
| `GET /actuator/health` | Public | Aggregate service health. |
| `GET /actuator/health/liveness` | Public | Process liveness probe. |
| `GET /actuator/health/readiness` | Public | Dependency readiness probe. |
| `GET /actuator` | Authenticated JWT | Actuator discovery document. |
| `GET /actuator/info` | Authenticated JWT | Application information. |
| `GET /actuator/prometheus` | Authenticated JWT | Prometheus metrics. |

Local orchestration and smoke tests use Actuator. `/health` remains for compatibility. Operational output must remain redacted; do not place tokens, credentials, raw PDF content, extracted customer fields, or secrets in logs, screenshots, or metric labels.

## Local startup

The recommended repository-level workflow builds the services, starts Oracle, provisions the shared schema, and launches the dependency chain in order:

```bash
./run-compose.sh up
```

Run that command from the repository root. Compose defaults to the unseeded `full-demo` schema profile; choose `runtime` during initial configuration for service-only development. See the [root README](../../README.md) for the required follow-up `verify` command and stack lifecycle details.

For host-based development, first run the shared database setup:

```bash
src/loan-application-service/setup-local-db.sh
```

That helper provisions both runtime accounts and applies the shared schema. Start `azn-server` on port `8080` and `loan-application-service` on port `8081`, then start document ingest from the repository root:

```bash
src/document-ingest/run-locally.sh
```

When already in the module directory, use `./run-locally.sh`.

When already in the module directory, use `./run-locally.sh`. The runner:

- defaults to port `8082`;
- silently prompts for the `CB_DOCUMENT_INGEST_APP` database password;
- silently prompts for the `cloudbank-document-ingest-client` OAuth secret;
- verifies the authorization and loan-service dependencies;
- does not display or save either secret.

For non-interactive use:

```bash
export DOCUMENT_INGEST_DATASOURCE_PASSWORD='<ingest-runtime-password>'
export DOCUMENT_INGEST_CLIENT_SECRET='<oauth-client-secret>'
./run-locally.sh
```

Relevant overrides are `PORT`, `DOCUMENT_INGEST_DATASOURCE_URL`, `DOCUMENT_INGEST_DATASOURCE_USERNAME`, `DOCUMENT_INGEST_SCHEMA`, `AZN_ISSUER_URI`, `AZN_JWK_SET_URI`, `DOCUMENT_INGEST_TOKEN_URI`, `DOCUMENT_INGEST_CLIENT_ID`, `DOCUMENT_INGEST_CALLER_CLIENT_IDS`, and `LOAN_APPLICATION_BASE_URL`.

Health checks are public at `http://127.0.0.1:8082/health` and `/actuator/health`. Business endpoints require a valid JWT.

## Running instance smoke test

`smoke-test.sh` performs a self-contained authenticated PDF-to-JSON check against a running `azn-server` and document-ingest service. It exercises the multipart diagnostic route; it does not call `loan-application-service` or create Oracle extraction rows.

From `src/document-ingest`:

```bash
./smoke-test.sh
```

For repository automation, run `./smoke-test.sh --non-interactive`. It reads
`INGEST_BASE_URL`, `AZN_BASE_URL`, `SERVICE_CLIENT_ID`, and
`SERVICE_CLIENT_SECRET` from the environment. The URLs and client ID retain
their local defaults; the client secret is required. `--show-json` can be used
with `--non-interactive`. Prefer the root `./run-compose.sh verify` command,
which supplies the Compose values without printing them.

For repository automation:

```bash
./smoke-test.sh --non-interactive
```

The script reads `INGEST_BASE_URL`, `AZN_BASE_URL`, `SERVICE_CLIENT_ID`, and `SERVICE_CLIENT_SECRET`. The URLs and client ID have local defaults; the client secret is required. `--show-json` may be combined with `--non-interactive`. Prefer root `./run-compose.sh verify`, which supplies Compose values without printing them.

The script obtains a signed service JWT directly from `azn-server`, verifies health and anonymous rejection, and submits these synthetic Elena Parker documents:

- `loan_application.pdf`
- `pay_statement_novereign_systems.pdf`
- `liability_schedule.pdf`

It verifies deterministic output by repeating the request. Successful output contains a conversion summary and an excerpt from the actual JSON response. To display the complete response:

```bash
./smoke-test.sh --show-json
```

When `jq` is installed, the response is pretty-printed; otherwise valid compact JSON is displayed. The component smoke test intentionally excludes loan-service BLOB retrieval, extraction persistence, and document-status callbacks because those require complete repository-level test state.

## Build and test

From the repository root:

```bash
mvn -f src/document-ingest/pom.xml test
mvn test
```

Tests use JUnit 5, Spring MVC test support, Mockito, and AssertJ. They cover:

- internal service-token authorization;
- all four extraction route mappings;
- PDF, ZIP, and multipart parsing;
- deterministic synthetic packet extraction;
- workflow retrieval, integrity verification, persistence, and status callbacks;
- authenticated loan-service client requests.

Tests read PDFs directly from `synthetic_data/customer_packets` and do not depend on packet manifests or generator internals. Workflow tests specifically exercise `loan_application.pdf` and `pay_statement_novereign_systems.pdf` from the Elena Parker synthetic packet.

## Troubleshooting

| Symptom | Likely cause and action |
| --- | --- |
| Startup cannot reach issuer metadata or JWKS | Start `azn-server`; verify `AZN_ISSUER_URI` and `AZN_JWK_SET_URI`. The configured issuer must exactly match the JWT `iss` claim. |
| `401 Unauthorized` | Obtain a fresh service token and verify its signature, expiry, issuer, and `aud=cloudbank-api`. |
| `403 Forbidden` | Verify `scope=cloudbank.internal`, `token_kind=service`, and that `client_id` is in `DOCUMENT_INGEST_CALLER_CLIENT_IDS`. |
| Outbound loan-service call cannot obtain a token | Verify `DOCUMENT_INGEST_TOKEN_URI`, `DOCUMENT_INGEST_CLIENT_ID`, and the silently supplied client secret. |
| Workflow reports no processable documents | Confirm the application exists, is authorized to the ingest client, and has document content in a processable status. |
| Document integrity verification fails | Compare loan-service manifest length and SHA-256 with the retrieved bytes. Do not bypass the check; the document is acknowledged as a final integrity failure. |
| Extraction is acknowledged as retryable | Inspect the redacted application, workflow, task, document, and trace correlation. Check PDF parsing, Oracle connectivity, and loan-service callback availability. |
| Extraction cannot be persisted | Rerun the shared setup, verify `CB_DOCUMENT_INGEST_APP` has `CB_DOCUMENT_INGEST_RUNTIME`, and keep the schema owner locked. |
| Multipart smoke test is rejected | Confirm the caller client is allow-listed and all three synthetic files exist under the Elena Parker packet directory. |
| ZIP output groups documents unexpectedly | Place PDFs under a consistent first-level directory inside the archive; that directory becomes the packet ID. |

Use application ID, workflow ID, task reference, document ID, extraction ID, and trace ID for investigation. Never include service tokens, client secrets, database passwords, raw PDFs, or sensitive extracted values in diagnostic output.
