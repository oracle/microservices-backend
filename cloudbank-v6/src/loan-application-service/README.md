# CloudBank Loan Application Service

`loan-application-service` is the durable intake and canonical application-status service for CloudBank loan origination. It creates applications, records expected document metadata, stores uploaded PDF content in secured Oracle SecureFiles BLOBs, creates audit/telemetry anchors, and schedules the MicroTx workflow through a transactional outbox.

It owns upload and authorized retrieval because the document is part of the application intake aggregate. It does not parse PDFs, interpret extraction output, make decisions, run AI tasks, or complete manual reviews.

## Contents

- [Quick start](#quick-start)
- [Security boundary](#security-boundary)
- [API](#api)
- [API examples](#api-examples)
- [Lifecycle and idempotency](#lifecycle-and-idempotency)
- [Errors](#errors)
- [Configuration](#configuration)
- [Operational endpoints](#operational-endpoints)
- [Build and test](#build-and-test)
- [Running instance smoke test](#running-instance-smoke-test)
- [OBaaS/OKE smoke test](#obaasoke-smoke-test)
- [Troubleshooting](#troubleshooting)

## Quick start

From the repository root, start the complete local stack and run its integration checks:

```bash
./run-compose.sh up
./run-compose.sh verify
```

Verify the loan service directly:

```bash
curl --fail-with-body http://127.0.0.1:8081/actuator/health
```

The default service URL is `http://127.0.0.1:8081`. `verify` obtains its own tokens and exercises the authenticated API; no token needs to be copied into the terminal. See [API examples](#api-examples) for development-time calls with an existing token, and the [root README](../../README.md) for stack lifecycle and reset commands.

## Security boundary

Every business endpoint is an OAuth2 resource-server endpoint. Tokens must be issued by `azn-server` and contain:

- the configured `iss` value
- `aud=cloudbank-api`
- `scope` containing the capability required by the endpoint
- `roles` containing CloudBank `ROLE_*` authorities
- `cb_principal_id` for user tokens
- `token_kind=service` and an allow-listed `client_id` for internal callbacks

The service enforces application ownership through the authenticated principal, active application roles, and `CB_DATA_GRANT` records. Oracle Deep Data Security is the planned future database enforcement layer.

Applicant principals are projected on first intake. Loan-officer, underwriter, auditor, operator, and administrator principals must be provisioned in `CB_APP_PRINCIPAL`/`CB_APP_ROLE_GRANT` with the same `cb_principal_id` issued by `azn-server`; an unmapped identity fails closed. The OKE deployment automatically provisions the sole lab profile, `obaas-admin`, with an active `ADMIN` grant covering all current and future applications. Other identities retain their existing access limits. See the [lab owner runbook](../../deploy/obaas/lab-owner-runbook.md). The OKE smoke-test wrapper defaults to this same account; an alternate `USERNAME` requires an explicit `USER_PASSWORD`.

The React UI must use the future Backend for Frontend (BFF) session boundary. It must not call this service directly or store bearer tokens, client secrets, signing material, or service credentials.

## API

All request and response bodies use JSON except PDF upload and download. The public resource-service endpoints are intended for trusted backend callers and development tools; browser traffic must use the BFF described in the [security boundary](#security-boundary).

| Method and endpoint | Success | Required access | Required input | Purpose |
| --- | --- | --- | --- | --- |
| `POST /api/v1/loan-applications` | `202` | `cloudbank.write`; `ROLE_APPLICANT`, `ROLE_LOAN_OFFICER`, or `ROLE_ADMIN` | JSON body and `Idempotency-Key` | Create intake and a workflow-start request. Returns `Location`. |
| `GET /api/v1/loan-applications` | `200` | `cloudbank.read`; `ROLE_APPLICANT`, `ROLE_LOAN_OFFICER`, `ROLE_UNDERWRITER`, `ROLE_AUDITOR`, or `ROLE_ADMIN` | Optional `status`, `scenarioId`, `page`, and `size` | List only database-authorized applications. |
| `GET /api/v1/loan-applications/{applicationId}` | `200` | `cloudbank.read`; `ROLE_APPLICANT`, `ROLE_LOAN_OFFICER`, `ROLE_UNDERWRITER`, `ROLE_AUDITOR`, or `ROLE_ADMIN` | Application ID | Read one authorized application. |
| `POST /api/v1/loan-applications/{applicationId}/documents` | `202` | `cloudbank.write`; `ROLE_APPLICANT`, `ROLE_LOAN_OFFICER`, or `ROLE_ADMIN` | JSON body and `Idempotency-Key` | Register additional expected document metadata. |
| `PUT /api/v1/loan-applications/{applicationId}/documents/{documentId}/content` | `200` | `cloudbank.write`; `ROLE_APPLICANT`, `ROLE_LOAN_OFFICER`, or `ROLE_ADMIN` | PDF body, `Content-Type: application/pdf`, and `Idempotency-Key` | Store one immutable PDF of 1 byte through 25 MiB. |
| `POST /api/v1/loan-applications/{applicationId}/workflow-start` | `202` | `cloudbank.write`; `ROLE_APPLICANT`, `ROLE_LOAN_OFFICER`, or `ROLE_ADMIN` | Application ID | Release a deferred workflow request. |
| `POST /internal/api/v1/loan-applications/{applicationId}/status-transitions` | `200` | `cloudbank.internal`; allow-listed service client | JSON body containing `eventId` | Apply an idempotent application status transition. |
| `GET /internal/api/v1/loan-applications/{applicationId}/documents` | `200` | `cloudbank.internal`; allow-listed service client | Application ID | Return the processable document manifest without bytes. |
| `GET /internal/api/v1/loan-applications/{applicationId}/documents/{documentId}/content` | `200` | `cloudbank.internal`; allow-listed service client | Application and document IDs | Stream an authorized PDF with `Cache-Control: private, no-store`. |
| `POST /internal/api/v1/loan-applications/{applicationId}/documents/{documentId}/status-transitions` | `200` | `cloudbank.internal`; allow-listed service client | JSON body containing `eventId` | Record an idempotent extraction status transition. |

`applicationId` values match `APP-...` and `documentId` values match `DOC-...`. List pagination is zero-based, defaults to `page=0&size=20`, and accepts `size` from 1 through 100.

### Intake request constraints

| Field | Accepted values |
| --- | --- |
| `scenarioId` / `scenarioName` | Nonblank; at most 80 / 200 characters. |
| `applicant.displayName` | Nonblank; at most 200 characters. |
| `applicant.phoneToken` / `emailToken` | Nonblank synthetic or tokenized values; at most 80 / 160 characters. Do not send raw credentials. |
| `applicant.ageBand` | `18-24`, `25-34`, `35-44`, `45-54`, `55-64`, or `65_PLUS`. |
| `loan.requestedAmount` | `1000.00` through `35000.00`. |
| `loan.requestedTermMonths` | `24`, `36`, `48`, or `60`. |
| `loan.purposeCode` | `DEBT_CONSOLIDATION`, `HOME_IMPROVEMENT`, `MAJOR_PURCHASE`, `MEDICAL_EXPENSE`, `HOUSEHOLD_EXPENSE`, `MOVING_EXPENSE`, or `OTHER_CONSUMER_PURPOSE`. |
| `loan.policyVersion` | Optional; at most 20 characters. |
| `documents` | 1 through 50 entries. New metadata must use `status: EXPECTED`. |
| `documents[].documentType` | `LOAN_APPLICATION`, `DISCLOSURE_CONSENT`, `IDENTITY_SUMMARY`, `ADDRESS_VERIFICATION`, `INCOME_VALIDATION`, `PAY_STATEMENT`, `DEPOSIT_SUMMARY`, `ACCOUNT_ACTIVITY`, `CONTRACTOR_INCOME`, `LIABILITY_SCHEDULE`, `PAYMENT_CALCULATION`, `CLARIFICATION_REQUEST`, `DOCUMENT_RECEIPT`, or `RELATIONSHIP_SIGNAL`. |
| `workflowStartMode` | `AUTO` or `DEFERRED`. |

When the service is running, an operator-authorized caller can use `/v3/api-docs` for the generated schema or `/swagger-ui/index.html` for the rendered API reference.

The application list is authorization-filtered in SQL: results, `totalElements`, and `totalPages` count only
applications the caller owns or can access through an active `ADMIN`/`SERVICE` role grant or data grant. The list
uses a stable CloudBank-owned pagination envelope rather than Spring Data's internal page serialization:

```json
{
  "content": [],
  "page": {
    "number": 0,
    "size": 20,
    "totalElements": 0,
    "totalPages": 0
  }
}
```

## API examples

These examples are for backend development against a running local service. They deliberately use environment-variable placeholders and synthetic data. Do not commit or paste real tokens, credentials, customer data, or private keys into scripts, documentation, shell history, or logs. Browser code must not use these calls directly.

From the repository root, set the service URL, then obtain a short-lived user
token from `azn-server` as described in the next section:

```bash
export LOAN_BASE_URL='http://127.0.0.1:8081'
```

Set `ACCESS_TOKEN` with the supported local flow below or with an approved
external token source.

### Obtain a local user access token

`cloudbank-client` is a user-facing OAuth client. It uses Authorization Code
with PKCE and deliberately does not support `client_credentials`; tokens from
`cloudbank-service-client` are service tokens and cannot replace the user token
required by these public endpoints.

The repository smoke test is the preferred option when you only need to verify
the API because it obtains, uses, and clears a user token without displaying
it:

```bash
./src/loan-application-service/smoke-test.sh
```

For manual `curl` calls, the following local-development flow exports the user
token into the current shell without printing it. It assumes `azn-server` is
running on port `8080`, the ignored root `.env` contains the generated
`AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET`, and `jq`, `openssl`, and
`python3` are installed.

Generate a PKCE verifier, challenge, and OAuth state, then open the authorization
request in a browser:

```bash
export AZN_BASE_URL='http://127.0.0.1:8080'
BROWSER_CLIENT_ID='cloudbank-client'
REDIRECT_URI="$AZN_BASE_URL/login/oauth2/code/$BROWSER_CLIENT_ID"
PKCE_VERIFIER="$(openssl rand -base64 48 | tr '+/' '-_' | tr -d '=\n')"
PKCE_CHALLENGE="$(printf '%s' "$PKCE_VERIFIER" |
  openssl dgst -sha256 -binary | openssl base64 -A | tr '+/' '-_' | tr -d '=')"
OAUTH_STATE="$(openssl rand -hex 16)"

AUTHORIZATION_URL="$(jq -nr \
  --arg base "$AZN_BASE_URL" \
  --arg client "$BROWSER_CLIENT_ID" \
  --arg redirect "$REDIRECT_URI" \
  --arg challenge "$PKCE_CHALLENGE" \
  --arg state "$OAUTH_STATE" '
    $base + "/oauth2/authorize?" +
    ({response_type:"code", client_id:$client, redirect_uri:$redirect,
      scope:"openid cloudbank.read cloudbank.write",
      code_challenge:$challenge, code_challenge_method:"S256", state:$state}
     | to_entries | map("\(.key | @uri)=\(.value | @uri)") | join("&"))
  ')"
open "$AUTHORIZATION_URL"
```

Sign in as an authorized demo user, such as `obaas-user`. After login, copy the
complete callback URL from the browser address bar. A callback error page is
acceptable here; the short-lived `code` and `state` query parameters in its URL
are what the command-line client needs. Paste the URL only into this silent
shell prompt, not into source files, notes, chat, or shell history:

```bash
IFS= read -r -s -p 'OAuth callback URL: ' CALLBACK_URL
printf '\n'

AUTHORIZATION_CODE="$(CALLBACK_URL="$CALLBACK_URL" python3 -c '
import os, urllib.parse
print(urllib.parse.parse_qs(urllib.parse.urlparse(os.environ["CALLBACK_URL"]).query).get("code", [""])[0])
')"
RETURNED_STATE="$(CALLBACK_URL="$CALLBACK_URL" python3 -c '
import os, urllib.parse
print(urllib.parse.parse_qs(urllib.parse.urlparse(os.environ["CALLBACK_URL"]).query).get("state", [""])[0])
')"
if [[ -z "$AUTHORIZATION_CODE" ]]; then
  printf 'Authorization code is missing; repeat the authorization request\n' >&2
elif [[ "$RETURNED_STATE" != "$OAUTH_STATE" ]]; then
  printf 'OAuth state mismatch; discard this callback and repeat the authorization request\n' >&2
  AUTHORIZATION_CODE=''
fi
```

Exchange the single-use code and export the resulting access token. The browser
client secret is read without displaying it and is passed to `curl` through
standard input rather than a command-line argument:

```bash
BROWSER_CLIENT_SECRET="$(awk -F= '
  $1 == "AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET" {
    sub(/^[^=]*=/, ""); print; exit
  }
' .env)"
if [[ -z "${AUTHORIZATION_CODE:-}" ]]; then
  printf 'No verified authorization code is available; repeat the authorization request\n' >&2
elif [[ -z "$BROWSER_CLIENT_SECRET" ]]; then
  printf 'Browser client secret is missing from .env\n' >&2
else
  CURL_USER="$BROWSER_CLIENT_ID:$BROWSER_CLIENT_SECRET"
  CURL_USER="${CURL_USER//\\/\\\\}"
  CURL_USER="${CURL_USER//\"/\\\"}"
  TOKEN_RESPONSE="$({
    printf 'user = "%s"\n' "$CURL_USER"
  } | curl --silent --show-error --fail --config - \
    --request POST \
    --url "$AZN_BASE_URL/oauth2/token" \
    --header 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=authorization_code' \
    --data-urlencode "code=$AUTHORIZATION_CODE" \
    --data-urlencode "redirect_uri=$REDIRECT_URI" \
    --data-urlencode "code_verifier=$PKCE_VERIFIER")"

  export ACCESS_TOKEN="$(printf '%s' "$TOKEN_RESPONSE" |
    jq -er '.access_token | strings | select(length > 0)')"
fi
unset AUTHORIZATION_CODE AUTHORIZATION_URL BROWSER_CLIENT_SECRET CALLBACK_URL
unset CURL_USER OAUTH_STATE PKCE_CHALLENGE PKCE_VERIFIER RETURNED_STATE TOKEN_RESPONSE
```

`ACCESS_TOKEN` is now available to the API examples below. Keep it only for the
current development session and run `unset ACCESS_TOKEN` when finished. Never
commit, print, log, or paste the token. Browser/UI code must continue to use the
approved BFF boundary and must not store raw access tokens.

### Create an application

```bash
curl --fail-with-body -i \
  --request POST \
  --url "$LOAN_BASE_URL/api/v1/loan-applications" \
  --header "Authorization: Bearer $ACCESS_TOKEN" \
  --header 'Content-Type: application/json' \
  --header 'Idempotency-Key: readme-create-001' \
  --data @- <<'JSON'
{
  "scenarioId": "README-DEMO-001",
  "scenarioName": "Synthetic README Loan Intake",
  "applicant": {
    "displayName": "Synthetic Applicant",
    "phoneToken": "synthetic-phone-token",
    "emailToken": "synthetic-email-token",
    "ageBand": "35-44",
    "address": {
      "addressLine": "6 East Orison Crossing",
      "locality": "East Orison",
      "jurisdictionCode": "CX",
      "addressToken": "synthetic-address-token"
    }
  },
  "loan": {
    "requestedAmount": 5000.00,
    "requestedTermMonths": 24,
    "purposeCode": "OTHER_CONSUMER_PURPOSE",
    "policyVersion": "2026.0"
  },
  "documents": [
    {
      "documentType": "LOAN_APPLICATION",
      "fileName": "loan_application.pdf",
      "status": "EXPECTED",
      "required": true,
      "mediaType": "application/pdf"
    }
  ],
  "workflowStartMode": "DEFERRED"
}
JSON
```

Address requests may also include optional `countryCode` (ISO 3166-1 alpha-2)
and `postalCode` fields. Geographic-risk-service uses them when it must resolve
missing coordinates through Oracle GCDR.

Creation returns `202 Accepted`, a resource location, and the canonical application representation:

```http
Location: /api/v1/loan-applications/APP-<generated-id>
```

```json
{
  "applicationId": "APP-<generated-id>",
  "scenarioId": "README-DEMO-001",
  "scenarioName": "Synthetic README Loan Intake",
  "status": "SUBMITTED",
  "requestedAmount": 5000.00,
  "requestedTermMonths": 24,
  "purposeCode": "OTHER_CONSUMER_PURPOSE",
  "documents": [
    {
      "documentId": "DOC-<generated-id>",
      "documentType": "LOAN_APPLICATION",
      "documentLabel": "Loan application",
      "fileName": "loan_application.pdf",
      "status": "EXPECTED",
      "required": true
    }
  ],
  "workflow": {
    "startRequestId": "WFR-<generated-id>",
    "workflowName": "cloudbank-loan-origination",
    "workflowVersion": 1,
    "dispatchStatus": "DEFERRED",
    "workflowId": null
  },
  "traceId": "<generated-trace-id>",
  "createdAt": "<timestamp>",
  "updatedAt": "<timestamp>"
}
```

Use the generated identifiers from the response for the remaining calls:

```bash
export APPLICATION_ID='APP-<generated-id>'
export DOCUMENT_ID='DOC-<generated-id>'
```

### List and read applications

```bash
curl --fail-with-body \
  --get \
  --url "$LOAN_BASE_URL/api/v1/loan-applications" \
  --header "Authorization: Bearer $ACCESS_TOKEN" \
  --data-urlencode 'status=SUBMITTED' \
  --data-urlencode 'scenarioId=README-DEMO-001' \
  --data-urlencode 'page=0' \
  --data-urlencode 'size=20'

curl --fail-with-body \
  --url "$LOAN_BASE_URL/api/v1/loan-applications/$APPLICATION_ID" \
  --header "Authorization: Bearer $ACCESS_TOKEN"
```

### Register another expected document

```bash
curl --fail-with-body \
  --request POST \
  --url "$LOAN_BASE_URL/api/v1/loan-applications/$APPLICATION_ID/documents" \
  --header "Authorization: Bearer $ACCESS_TOKEN" \
  --header 'Content-Type: application/json' \
  --header 'Idempotency-Key: readme-document-001' \
  --data '{"documents":[{"documentType":"PAY_STATEMENT","fileName":"pay_statement_novereign_systems.pdf","status":"EXPECTED","required":true,"mediaType":"application/pdf"}]}'
```

The response contains the newly generated document ID. Keep `DOCUMENT_ID` set to the original loan-application document for the next example, or set a separate identifier for the new pay-statement document.

### Upload an immutable PDF

```bash
export PDF_PATH='synthetic_data/customer_packets/app_apr_001_elena_parker/loan_application.pdf'

curl --fail-with-body \
  --request PUT \
  --url "$LOAN_BASE_URL/api/v1/loan-applications/$APPLICATION_ID/documents/$DOCUMENT_ID/content" \
  --header "Authorization: Bearer $ACCESS_TOKEN" \
  --header 'Content-Type: application/pdf' \
  --header 'Idempotency-Key: readme-upload-001' \
  --data-binary "@$PDF_PATH"
```

Reuploading identical bytes is safe. Uploading different bytes after content has been stored returns `409 DOCUMENT_CONTENT_CONFLICT` because document content is immutable.

### Release a deferred workflow

```bash
curl --fail-with-body \
  --request POST \
  --url "$LOAN_BASE_URL/api/v1/loan-applications/$APPLICATION_ID/workflow-start" \
  --header "Authorization: Bearer $ACCESS_TOKEN"
```

This endpoint does not use `Idempotency-Key`; repeated release requests are safe
after the workflow becomes `PENDING`, `IN_PROGRESS`, `FAILED_RETRYABLE`, or
`STARTED`. They reconcile the existing request without resetting dispatch or
creating another workflow. Terminal failure and cancellation remain conflicts.

### Service-to-service examples

Internal endpoints require a `cloudbank.internal` service token whose `client_id` is in `LOAN_INTERNAL_CLIENT_IDS`. They are not browser APIs.

```bash
export SERVICE_ACCESS_TOKEN='<short-lived-allow-listed-service-token>'

curl --fail-with-body \
  --url "$LOAN_BASE_URL/internal/api/v1/loan-applications/$APPLICATION_ID/documents" \
  --header "Authorization: Bearer $SERVICE_ACCESS_TOKEN"

curl --fail-with-body \
  --url "$LOAN_BASE_URL/internal/api/v1/loan-applications/$APPLICATION_ID/documents/$DOCUMENT_ID/content" \
  --header "Authorization: Bearer $SERVICE_ACCESS_TOKEN" \
  --output /tmp/cloudbank-synthetic-document.pdf

curl --fail-with-body \
  --request POST \
  --url "$LOAN_BASE_URL/internal/api/v1/loan-applications/$APPLICATION_ID/documents/$DOCUMENT_ID/status-transitions" \
  --header "Authorization: Bearer $SERVICE_ACCESS_TOKEN" \
  --header 'Content-Type: application/json' \
  --data '{"eventId":"EVT-README-DOC-001","expectedStatus":"RECEIVED","targetStatus":"EXTRACTED","reasonCode":"SYNTHETIC_EXTRACTION_COMPLETE","traceId":"readme-trace-001"}'
```

Application transitions use the same event-id pattern:

```bash
curl --fail-with-body \
  --request POST \
  --url "$LOAN_BASE_URL/internal/api/v1/loan-applications/$APPLICATION_ID/status-transitions" \
  --header "Authorization: Bearer $SERVICE_ACCESS_TOKEN" \
  --header 'Content-Type: application/json' \
  --data '{"eventId":"EVT-README-APP-001","expectedStatus":"SUBMITTED","targetStatus":"PROCESSING","reasonCode":"SYNTHETIC_WORKFLOW_STARTED","traceId":"readme-trace-001"}'
```

## Lifecycle and idempotency

- `workflowStartMode=AUTO` allows dispatch when all required documents have content. An intake with missing required content starts as `WAITING_FOR_DOCUMENTS` and is promoted when uploads complete.
- `workflowStartMode=DEFERRED` keeps dispatch at `DEFERRED` until the workflow-start endpoint releases it.
- `WORKFLOW_MODE=fake|microtx` selects the configured dispatch backend. It is separate from request-level `workflowStartMode`.
- New applications start at `SUBMITTED`. Application states are `SUBMITTED`, `DOCUMENTS_RECEIVED`, `PROCESSING`, `MANUAL_REVIEW`, `APPROVED`, `REJECTED`, `FAILED_RETRYABLE`, `RECOVERED`, `WITHDRAWN`, and `EXPIRED`.
- Document states are `EXPECTED`, `RECEIVED`, `EXTRACTED`, `VALIDATED`, `NEEDS_REVIEW`, `FAILED_RETRYABLE`, and `FAILED_FINAL`.
- Workflow dispatch states are `WAITING_FOR_DOCUMENTS`, `DEFERRED`, `PENDING`, `IN_PROGRESS`, `STARTED`, `FAILED_RETRYABLE`, `FAILED_FINAL`, and `CANCELLED`.

Creation, metadata registration, and PDF upload require `Idempotency-Key` containing 8–200 letters, numbers, `.`, `_`, `:`, or `-`. Retrying creation or registration with the same key and same canonical request returns the existing result; reusing the key for a different request returns `409 IDEMPOTENCY_CONFLICT`. PDF retries are reconciled by the stored SHA-256 digest: identical content succeeds and different content conflicts.

Internal transitions do not use the header. Their `eventId` is the durable idempotency key, and `expectedStatus` provides optimistic concurrency protection. Workflow release is state-idempotent and requires no request body or idempotency header.

## Errors

Errors use one stable envelope:

```json
{
  "code": "IDEMPOTENCY_CONFLICT",
  "message": "The idempotency key was already used for a different request",
  "correlationId": "<generated-correlation-id>",
  "retryable": false,
  "authorizationStatus": null,
  "fieldErrors": []
}
```

| Status | Typical meaning |
| --- | --- |
| `401 Unauthorized` | Token is missing, expired, incorrectly signed, or has the wrong issuer or audience. |
| `403 Forbidden` | Scope, role, or the internal client allow-list check failed. |
| `404 Not Found` | The resource is absent or deliberately hidden from the authenticated principal. |
| `409 Conflict` | An idempotency key, immutable PDF, expected status, or workflow state conflicts with current state. |
| `413 Payload Too Large` | PDF is empty or exceeds 25 MiB. |
| `415 Unsupported Media Type` | Uploaded content is not `application/pdf`. |
| `422 Unprocessable Entity` | Request fields, identifiers, terms, purposes, document types, or initial statuses are invalid. |
| `500 Internal Server Error` | An unexpected failure occurred; use `correlationId` to find the redacted server-side log event. |

## Configuration

Application defaults are shown below. Database passwords, OAuth client secrets, tokens, and signing material must be supplied through silent prompts, environment variables, or platform secret configuration and must never be committed.

### Database and HTTP

| Variable | Default | Required when | Purpose |
| --- | --- | --- | --- |
| `PORT` | `8081` | Optional | HTTP port. |
| `LOAN_DATASOURCE_URL` | Falls back to `SPRING_DATASOURCE_URL`; otherwise empty | Always, unless the fallback is set | Oracle JDBC URL. |
| `LOAN_DATASOURCE_USERNAME` | `CB_LOAN_APPLICATION_APP` | Optional | Least-privilege runtime account. |
| `LOAN_DATASOURCE_PASSWORD` | None | Always | Runtime database password; secret. |
| `LOAN_SCHEMA` | `CLOUDBANK` | Optional | Hibernate validation schema. |

### Authorization

| Variable | Default | Required when | Purpose |
| --- | --- | --- | --- |
| `AZN_ISSUER_URI` | `http://127.0.0.1:8080` | Override outside local development | Required JWT issuer. |
| `AZN_JWK_SET_URI` | `http://127.0.0.1:8080/oauth2/jwks` | Override outside local development | Signing-key endpoint. |
| `AZN_AUDIENCE` | `cloudbank-api` | Optional | Required JWT audience. |
| `LOAN_INTERNAL_CLIENT_IDS` | `cloudbank-service-client,cloudbank-document-ingest-client` | Override for deployed service clients | Allow-list for internal API callers. |

### Workflow and platform integration

| Variable | Default | Required when | Purpose |
| --- | --- | --- | --- |
| `WORKFLOW_MODE` | `fake` | Optional | Dispatch backend: `fake` or `microtx`. |
| `WORKFLOW_DISPATCH_DELAY_MS` | `1000` | Optional | Outbox dispatch polling delay. |
| `MICROTX_WORKFLOW_URL` | None | `WORKFLOW_MODE=microtx` | MicroTx workflow endpoint. |
| `MICROTX_WORKFLOW_NAME` | `cloudbank-loan-origination` | Optional | Saved workflow name. |
| `MICROTX_TOKEN_URI` | None | `WORKFLOW_MODE=microtx` | OAuth token endpoint for workflow dispatch. |
| `MICROTX_CLIENT_ID` | `microtx-workflow-client` | Optional | Dedicated MicroTx Workflow API client ID. |
| `MICROTX_CLIENT_SECRET` | None | `WORKFLOW_MODE=microtx` | Workflow service-client secret. |
| `MICROTX_SCOPE` | `microtx.workflow` | Optional | Scope requested for the dedicated MicroTx Workflow API token. |
| `WORKFLOW_TASK_TOKEN_URI` | `MICROTX_TOKEN_URI` | `WORKFLOW_MODE=microtx` | Token endpoint used for downstream workflow task authorization. |
| `WORKFLOW_MAX_DISPATCH_ATTEMPTS` | `5` | Optional | Maximum workflow-start attempts, including retries for transient MicroTx `404`, `429`, and `5xx` responses. |
| `WORKFLOW_TASK_CLIENT_ID` | `cloudbank-service-client` | `WORKFLOW_MODE=microtx` | CloudBank service identity placed in workflow task authorization. |
| `WORKFLOW_TASK_CLIENT_SECRET` | None | `WORKFLOW_MODE=microtx` | Secret for the downstream CloudBank service identity. |
| `WORKFLOW_TASK_SCOPE` | `cloudbank.internal` | Optional | Scope requested for downstream CloudBank workflow tasks. |
| `EUREKA_CLIENT_ENABLED` | `false` | Optional | Enable service registration and discovery. |
| `EUREKA_SERVER_ADDRESS` | `http://localhost:8761/eureka/` | When Eureka is enabled outside that default | Eureka server URL. |

The runtime database identity should receive `CB_LOAN_APPLICATION_RUNTIME`; it must not connect as the schema owner.

Spring virtual threads are enabled through `spring.threads.virtual.enabled=true`, matching `azn-server`. Request
handling and Spring-managed task execution can use virtual threads, while Oracle UCP continues to bound database
concurrency with its configured connection-pool limits.

Persistence code uses Spring's fluent `JdbcClient` with named parameters. It runs through the same Oracle UCP
datasource and Spring-managed transaction boundaries used by the service and does not provide reactive database I/O.

Local and deterministic test runs default to `WORKFLOW_MODE=fake`. Live mode requires the MicroTx URL, token URI, client ID, and client secret listed above and assumes `cloudbank-loan-origination` version `1` has already been created and saved in MicroTx. This service starts executions; it does not deploy the workflow definition. The current REST start path is an adapter assumption that still requires verification against the target MicroTx 26.1 installation. See [MICROTX_INTEGRATION.md](MICROTX_INTEGRATION.md) for the request/response contract, security model, retry behavior, workflow-definition requirements, deployment checklist, and known gaps.

The workflow version is fixed to `1` in the application code and has no
environment-variable override.

## Operational endpoints

| Endpoint | Access | Purpose |
| --- | --- | --- |
| `GET /actuator/health` | Public | Aggregate service health. |
| `GET /actuator/health/liveness` | Public | Process liveness probe. |
| `GET /actuator/health/readiness` | Public | Dependency readiness probe. |
| `GET /actuator/info` | `ROLE_OPERATOR` | Build and application information. |
| `GET /actuator/prometheus` | `ROLE_OPERATOR` | Prometheus metrics. |
| `GET /v3/api-docs` | `ROLE_OPERATOR` | Generated OpenAPI JSON. |
| `GET /swagger-ui/index.html` | `ROLE_OPERATOR` | Interactive OpenAPI UI. |

Operational output must remain redacted. Do not place bearer tokens, credentials, raw customer content, or workflow secrets in logs, screenshots, metrics labels, or sample output.

## Build and test

From the repository root:

```bash
mvn -f src/loan-application-service/pom.xml test
mvn test
```

Oracle schema objects are managed centrally by `src/schema/changelog-root.xml`; Hibernate does not create or update schema objects.

The loan application service does not use Oracle Spatial directly. The
`runtime` schema profile therefore remains usable without Spatial. The default
Compose `full-demo` profile verifies Spatial and Text support, installs the
optional feature objects, and loads the minimal `APP-RISK-005` spatial fixture
used by the geographic-risk-service smoke test.

### Local database setup

The recommended repository-level workflow starts Oracle, runs this setup as a
one-shot initializer, builds all services, and waits for the complete stack:

```bash
./run-compose.sh up
```

Run that command from the repository root. See the
[root README](../../README.md) for the required follow-up `verify` command,
stack lifecycle, persistence, and reset details. The standalone database and
service helpers below remain available for an existing host database.

From `src/loan-application-service`, provision or update all Oracle objects required by this service:

```bash
./setup-local-db.sh
```

The script defaults to `SYSTEM@//localhost:1521/freepdb1`, explains each credential, and silently prompts for the existing database-administrator password, a `CLOUDBANK` schema-owner password, the loan and document-ingest runtime passwords, and the geographic-risk runtime password when `SCHEMA_PROFILE=full-demo`. The owner password must differ from runtime passwords. Runtime accounts may share a password for local development, although deployed environments should use distinct service credentials. It does not hardcode, display, save, or pass passwords as operating-system command arguments.

The setup uses SQLcl Liquibase from the canonical
`src/schema/changelog-root.xml`. Direct invocation defaults to
`SCHEMA_PROFILE=runtime`; set `SCHEMA_PROFILE=full-demo` to apply both label
groups and verify Spatial, Text, Vector, Property Graph, and annotations.
Neither profile loads `seed-data.json`; `full-demo` only adds the minimal
geographic-risk smoke fixture. It creates or updates
accounts, grants the
least-privilege runtime roles, removes temporary migration privileges, locks
the schema owner, verifies the resulting database contract, and authenticates
each runtime account with the supplied credential. Repeated execution handles
ADB's unchanged-password reuse response without regenerating credentials. No VPD
policies or application contexts are installed (ADR 0013); application access
is enforced by interim service-side ownership, role, and data-grant checks
until Deep Data Security replaces them. If any phase fails, the script attempts to
remove temporary privileges and relock the owner before exiting.

SQLcl runs Liquibase from the `src/schema` search path and addresses the changelog by its relative name. This is required by Liquibase secure path handling; an absolute changelog filename is rejected even when it points inside the configured search path.

The setup is safe to rerun after an interrupted first migration. The document-table migration recognizes the complete table set left by Oracle's statement-level DDL commits, records that recovered step, and continues with its separate runtime-index change set. Constraint-backed indexes are not recreated, and JSON search indexes remain in the optional `full-demo` path because lightweight images may not provide Oracle Text/Search.

For non-interactive automation, provide every secret through the environment:

```bash
export LOAN_DB_ADMIN_USERNAME='SYSTEM'
export LOAN_DB_ADMIN_PASSWORD='<database-administrator-password>'
export LOAN_SCHEMA_OWNER_PASSWORD='<schema-owner-password>'
export LOAN_DATASOURCE_PASSWORD='<runtime-password>'
export DOCUMENT_INGEST_DATASOURCE_PASSWORD='<same-or-different-ingest-runtime-password>'
export LOAN_SQLCL_CONNECT='//localhost:1521/freepdb1'
export SCHEMA_PROFILE='full-demo'

./setup-local-db.sh
```

Schema passwords must be 12-128 characters and contain an uppercase letter, lowercase letter, number, and one of `#`, `!`, `?`, `$`, `%`, `^`, `*`, `_`, or `-`. SQLcl must be installed and available as `sql`.

### Local service startup

After database setup, start `azn-server` on port `8080`, then invoke the helper
from either the repository root or `src/loan-application-service`:

```bash
src/loan-application-service/run-locally.sh
```

When already in the module directory, use `./run-locally.sh`.

The runner starts `loan-application-service` on port `8081`. It silently prompts only for the `CB_LOAN_APPLICATION_APP` runtime password; it neither needs nor accepts the `SYSTEM` or locked `CLOUDBANK` owner passwords. Exported values are reused for non-interactive execution:

```bash
export LOAN_DATASOURCE_PASSWORD='<runtime-password>'
./run-locally.sh
```

Before Maven starts, the runner verifies the configured `azn-server` OIDC metadata and JWKS endpoints. Defaults are `AZN_ISSUER_URI=http://127.0.0.1:8080`, `AZN_JWK_SET_URI=http://127.0.0.1:8080/oauth2/jwks`, and `AZN_AUDIENCE=cloudbank-api`. If schema validation or database authentication fails during Spring startup, rerun `./setup-local-db.sh` with the intended credentials.

The local workflow backend defaults to `fake`, which requires no MicroTx instance. This backend setting is separate from an intake request's `workflowStartMode`: the smoke test defaults requests to `DEFERRED`, so they remain deferred even while the configured backend is `fake`.

To use a live MicroTx workflow, provide its required configuration before startup:

```bash
export WORKFLOW_MODE='microtx'
export MICROTX_WORKFLOW_URL='https://<microtx-workflow-endpoint>'
export MICROTX_WORKFLOW_NAME='cloudbank-loan-origination'
export MICROTX_TOKEN_URI='http://127.0.0.1:8080/oauth2/token'
export MICROTX_CLIENT_ID='microtx-workflow-client'
export MICROTX_CLIENT_SECRET='<microtx-client-secret>'
export WORKFLOW_TASK_CLIENT_ID='cloudbank-service-client'
export WORKFLOW_TASK_CLIENT_SECRET='<cloudbank-service-client-secret>'

./run-locally.sh
```

The two credentials are intentionally distinct. The MicroTx token has audience
`microtx-workflow` and is sent only to the Workflow API. The workflow task token
has audience `cloudbank-api` and is the only token placed in
`workflowTaskAuthorization` for the protected version 1 HTTP tasks: document
extraction, document review, AI document-evidence summary, and policy-evidence
retrieval.

Live MicroTx mode requires complete credentials for both trust domains. The
dedicated MicroTx credential authorizes only the Workflow API request; the
separate CloudBank workflow-task credential produces the short-lived token
placed in workflow input and relayed only to the protected CloudBank task
endpoints. The runner silently prompts for both `MICROTX_CLIENT_SECRET` and
`WORKFLOW_TASK_CLIENT_SECRET` when they are not exported.
`WORKFLOW_MODE=deferred` is rejected because deferred is an intake start mode,
not a dispatch backend.

`workflowTaskAuthorization` is an interim, sensitive integration mechanism. MicroTx may retain workflow input as execution state or history, and a delayed or retried task may outlive the token. Do not expose the value in logs, traces, Workbench screenshots, or API samples. Before enabling live traffic, verify input visibility and access controls, token lifetime behavior, and replacement options for platform-managed task authentication.

Additional implementation references:

- [Loan document intake and extraction](../../docs/architecture/loan-document-intake-and-extraction.md) is the end-to-end developer guide for application creation, SecureFiles upload, workflow dispatch, authenticated document retrieval, JSON extraction, and acknowledgement.
- [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) records the service-level design and delivery status.
- [MICROTX_INTEGRATION.md](MICROTX_INTEGRATION.md) is the detailed live workflow integration handoff.

## Running instance smoke test

`smoke-test.sh` runs an authenticated end-to-end check against a running loan application service and `azn-server`. It automates the real authorization-code and PKCE login so `azn-server` signs the user JWT; the operator does not copy or paste tokens. It also requests a service JWT for the internal workflow callback.

From `src/loan-application-service`:

```bash
./smoke-test.sh
```

The script prompts for service URLs, demo-user credentials, browser-client credentials, service-client credentials, and one of these workflow modes. The selected demo user must have `ROLE_APPLICANT`, `ROLE_LOAN_OFFICER`, or `ROLE_ADMIN`; fresh local environments normally use `obaas-user` with `ROLE_APPLICANT`:

- `deferred` (default) creates a deferred workflow request and does not contact MicroTx.
- `fake` exercises the local deterministic workflow starter and requires a `fake-` workflow ID.
- `microtx` exercises a configured live MicroTx instance and requires a non-fake workflow ID.

The script displays these descriptions before asking for a mode. It asks for a workflow polling timeout only for
`fake` and `microtx`; `deferred` does not poll and therefore requires no timeout.

#### Where the interactive credentials come from

For the repository-managed local Compose environment, the credentials are in
the ignored `.env` file at the repository root:

```text
cloudbank-ai/.env
```

If that file does not exist yet, create and validate the local configuration
from the repository root:

```bash
./run-compose.sh init
```

`init` generates strong local-only credentials without displaying them and
does not overwrite an existing `.env`. When `smoke-test.sh` prompts for a
secret, open the local `.env` in a trusted editor and paste only the value after
the matching `=`; do not enter the variable name or the `=` character:

| Smoke-test prompt | Find this entry in root `.env` | What it authenticates |
| --- | --- | --- |
| `Demo user password:` | `AZN_BOOTSTRAP_USERS_USER_PASSWORD` | Password for the default `obaas-user` login used by the Authorization Code/PKCE flow. |
| `Browser OAuth client secret:` | `AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET` | Secret for the default `cloudbank-client` authorization-code client. |
| `Service OAuth client secret:` | `AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET` | Secret for `cloudbank-service-client`, used to test the internal service API. |

For example, if `.env` contains
`AZN_BOOTSTRAP_USERS_USER_PASSWORD=<generated-value>`, enter only
`<generated-value>` at `Demo user password:`. The prompt is silent, so no
characters appear while typing or pasting; press Return after each value.

Do not use `AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET` for any of these
prompts. That credential belongs only to the MicroTx Workflow API. If the test
targets an externally deployed `azn-server`, obtain the equivalent demo-user,
browser-client, and service-client credentials from that environment's
approved secret store instead of the local `.env`.

Use this mapping when answering the interactive prompts or preparing a
non-interactive run:

| Interactive prompt | Smoke-test environment variable | Local default | Canonical root `.env` source |
| --- | --- | --- | --- |
| Loan Application Service base URL | `LOAN_BASE_URL` | `http://127.0.0.1:8081` | No secret entry; use the URL reachable from the shell running the test. |
| `azn-server` base URL | `AZN_BASE_URL` | `http://127.0.0.1:8080` | Usually the local `AZN_ISSUER_URI`; use the URL reachable from the test process. |
| Demo username | `USERNAME` | `obaas-user` | No generated entry; `obaas-user` is the standard local applicant. |
| Demo user password | `USER_PASSWORD` | Root `.env` value in non-interactive mode | `AZN_BOOTSTRAP_USERS_USER_PASSWORD` |
| Browser OAuth client ID | `BROWSER_CLIENT_ID` | `cloudbank-client` | `AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_ID` when overridden; otherwise use the default. |
| Browser OAuth client secret | `BROWSER_CLIENT_SECRET` | Root `.env` value in non-interactive mode | `AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET` |
| Registered redirect URI | `REDIRECT_URI` | `$AZN_BASE_URL/login/oauth2/code/$BROWSER_CLIENT_ID` | `AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_REDIRECT_URI` when overridden; otherwise use the default. |
| Service OAuth client ID | `SERVICE_CLIENT_ID` | `cloudbank-service-client` | `AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_ID` when overridden; otherwise use the default. |
| Service OAuth client secret | `SERVICE_CLIENT_SECRET` | Root `.env` value in non-interactive mode | `AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET` |
| Workflow mode | `WORKFLOW_MODE` | `deferred` | `deferred`, `fake`, or `microtx`; this selects smoke-test behavior, not the service's runtime configuration. |
| Workflow polling timeout | `WORKFLOW_TIMEOUT` | `30` seconds | Used only for `fake` and `microtx`; valid range is 1–999 seconds. |

In `--non-interactive` mode, the module smoke test reads the three required
secret values directly from the repository-root `.env` without sourcing or
executing the file:

- `AZN_BOOTSTRAP_USERS_USER_PASSWORD` supplies `USER_PASSWORD`.
- `AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET` supplies
  `BROWSER_CLIENT_SECRET`.
- `AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET` supplies
  `SERVICE_CLIENT_SECRET`.

Run it from the repository root with:

```bash
WORKFLOW_MODE='deferred' \
./src/loan-application-service/smoke-test.sh --non-interactive
```

Explicit `USER_PASSWORD`, `BROWSER_CLIENT_SECRET`, or
`SERVICE_CLIENT_SECRET` environment variables override the corresponding
`.env` entries. Set `CLOUDBANK_ENV_FILE` to use another environment file.

For a configured fake or live MicroTx backend, change `WORKFLOW_MODE` to
`fake` or `microtx` and optionally add `WORKFLOW_TIMEOUT='30'`. The service
itself must already be running with the matching backend configuration. The
smoke test does not need or accept MicroTx client secrets because the Loan
Application Service, not the test caller, owns workflow dispatch credentials.

To exercise the `MANUAL_REVIEW` workflow branch against live MicroTx, add
`--manual-review`:

```bash
WORKFLOW_MODE='microtx' \
./src/loan-application-service/smoke-test.sh --non-interactive --manual-review
```

This option selects the packet's ready `manual-review/loan_application.pdf` with `Lumenfield Analytics` as
the declared employer while the uploaded pay statement identifies
`Novereign Systems Cooperative`. The deterministic document-review rule emits
`EMPLOYER_INCONSISTENCY` and routes the application to `MANUAL_REVIEW`. The
default invocation keeps matching employer evidence and continues to exercise
the `CLEAR` path.

For repository automation, run `./smoke-test.sh --non-interactive`. It reads
`LOAN_BASE_URL`, `AZN_BASE_URL`, `USERNAME`, `USER_PASSWORD`,
`BROWSER_CLIENT_ID`, `BROWSER_CLIENT_SECRET`, `REDIRECT_URI`,
`SERVICE_CLIENT_ID`, `SERVICE_CLIENT_SECRET`, `WORKFLOW_MODE`, and
`WORKFLOW_TIMEOUT` from the environment. The URLs, username, client IDs, and
workflow mode have local defaults. When the three secret overrides are absent,
the script obtains them from the canonical root `.env` entries listed above.
`WORKFLOW_TIMEOUT` is used only for `fake` or `microtx`. Prefer the root
`./run-compose.sh verify` command for the complete component verification.

Passwords and client secrets are read silently. Tokens, OAuth codes, PKCE material, and cookies are never accepted as command-line arguments or printed. Temporary authentication files are owner-only and removed on exit. The script requires `curl`, `grep`, `sed`, `openssl`, and standard shell utilities.

The smoke test reads `synthetic_data/customer_packets/demo_geocoded_loan/application.json`
and its existing loan/pay-statement PDFs, also used by the GUI. Use
`--application-file FILE` to select another two-document packet. Scenario and
contact/address correlation values receive a fresh run ID. Intake assigns the
canonical application/document IDs, and uploads use only the returned metadata;
neither PDF generation nor an embedded application ID is required. The application
remains in Oracle for auditability. The test verifies immutable/idempotent upload,
anonymous/service-token rejection, ownership-aware reads, scheduling and status
transitions. `--manual-review` selects the packet's employer-conflict loan PDF;
inspect the execution for AI assistance and the HUMAN checkpoint. Temporary
authentication files are removed on exit; checked-in PDFs remain unchanged.
The script requires `jq` and exits with `0` when all checks pass, `1` for service
check failures and `2` for invalid setup/usage. Deploy the updated ingest/review
services with active profile `document-review-v2` before using this packet.

## OBaaS/OKE smoke test

`smoke-test-obaas.sh` adapts the authenticated loan smoke test to CloudBank
deployed on OBaaS/OKE. It discovers or validates the application namespace,
checks the required Deployments, Services, and ready EndpointSlices, confirms
that the Loan Application Service uses the live MicroTx workflow definition,
and creates private localhost port-forwards for `azn-server` and
`loan-application-service`. If either local port is already occupied, the
script reuses the existing port-forward. Only port-forwards started by this
script and the temporary authentication files are removed when it exits.

The first positional argument is the kubectl context. The namespace is
auto-detected when the context contains exactly one supported OBaaS release;
otherwise pass it explicitly:

```bash
./src/loan-application-service/smoke-test-obaas.sh \
  "$KUBECTL_CONTEXT" \
  --namespace "$OBAAS_NAMESPACE"
```

This default invocation is interactive. It requests the following values
through silent prompts and includes the corresponding root `.env` variable in
each prompt:

| Prompt | Root `.env` variable |
| --- | --- |
| Lab owner password (`obaas-admin`) | `AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD` |
| Browser OAuth client secret | `AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET` |
| Service OAuth client secret | `AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET` |

### Read credentials from `.env`

Use `--from-env` to run without credential prompts. The wrapper reads only the
three entries listed above from the repository-root `.env`; it does not source
or execute the file and does not display the values:

```bash
./src/loan-application-service/smoke-test-obaas.sh \
  "$KUBECTL_CONTEXT" \
  --namespace "$OBAAS_NAMESPACE" \
  --from-env
```

Explicit `USER_PASSWORD`, `BROWSER_CLIENT_SECRET`, and
`SERVICE_CLIENT_SECRET` environment variables take precedence over matching
`.env` entries. `--non-interactive` remains an alias for `--from-env`.
The default OKE username is `obaas-admin`. Selecting another `USERNAME`
requires an explicit `USER_PASSWORD`; access remains subject to that identity's
own grants.

Set `CLOUDBANK_ENV_FILE` to read another protected environment file:

```bash
CLOUDBANK_ENV_FILE='/path/to/protected/.env' \
./src/loan-application-service/smoke-test-obaas.sh \
  "$KUBECTL_CONTEXT" \
  --namespace "$OBAAS_NAMESPACE" \
  --from-env
```

### Standard and manual-review workflow paths

The standard invocation creates matching employer evidence and expects the
deterministic document-review path to produce `CLEAR`:

```bash
./src/loan-application-service/smoke-test-obaas.sh \
  "$KUBECTL_CONTEXT" \
  --namespace "$OBAAS_NAMESPACE" \
  --from-env
```

Add `--manual-review` to generate conflicting employer evidence and exercise
the `MANUAL_REVIEW` branch:

```bash
./src/loan-application-service/smoke-test-obaas.sh \
  "$KUBECTL_CONTEXT" \
  --namespace "$OBAAS_NAMESPACE" \
  --from-env \
  --manual-review
```

Without `--from-env`, the same workflow branch can be started interactively:

```bash
./src/loan-application-service/smoke-test-obaas.sh \
  "$KUBECTL_CONTEXT" \
  --namespace "$OBAAS_NAMESPACE" \
  --manual-review
```

The OBaaS wrapper always sets `WORKFLOW_MODE=microtx`, expects workflow
`cloudbank-loan-origination` version `1`, and uses request-level
`workflowStartMode=AUTO`. Use the base `smoke-test.sh`, not this wrapper, for
the local `deferred` or `fake` modes.

The test confirms that workflow dispatch reaches `STARTED`; it does not wait
for the asynchronous workflow to finish. For the standard path, inspect the
MicroTx execution to confirm completion of document extraction and review. For
the manual-review path, also confirm that the execution reaches the governed AI
assistant and HUMAN task. A successful wrapper exit alone does not prove that
those later tasks completed.

Optional runtime overrides are:

| Variable | Purpose | Default |
| --- | --- | --- |
| `OBAAS_AZN_LOCAL_PORT` | Local `azn-server` port-forward | `8080` |
| `OBAAS_LOAN_LOCAL_PORT` | Local Loan Application Service port-forward | `18081` |
| `WORKFLOW_TIMEOUT` | Maximum wait for dispatch to reach `STARTED` | `120` seconds |
| `CLOUDBANK_ENV_FILE` | Credential file used by `--from-env` | Repository-root `.env` |

Changing `OBAAS_AZN_LOCAL_PORT` also requires `REDIRECT_URI` to identify a URI
registered for the browser OAuth client. The script never accepts or prints a
MicroTx client secret: the deployed Loan Application Service owns workflow
dispatch authentication. Each run creates a uniquely labeled synthetic
application that remains in Oracle for auditability.

## Troubleshooting

| Symptom | Likely cause and action |
| --- | --- |
| Startup cannot reach issuer metadata or JWKS | Start `azn-server`, then verify `AZN_ISSUER_URI` and `AZN_JWK_SET_URI`. The issuer must exactly match the JWT `iss` claim. |
| `401 AUTHENTICATION_REQUIRED` | Obtain a fresh token from `azn-server`; verify its signature, expiry, `iss`, and `aud=cloudbank-api`. |
| `403 ACCESS_DENIED` | Verify the required scope and role. For an internal call, also verify `token_kind=service`, `cloudbank.internal`, and the configured client allow-list. |
| Authorized staff token still cannot read data | For the OKE lab's `obaas-admin`, run `deploy/obaas/provision-lab-admin.sh` as described in the lab owner runbook. Other staff require explicit provisioning of the token's `cb_principal_id` in `CB_APP_PRINCIPAL` and `CB_APP_ROLE_GRANT`. Applicant ownership is projected on first intake. |
| `404 APPLICATION_NOT_FOUND` for an existing ID | The service intentionally hides applications the principal cannot access through its ownership, role, and data-grant checks. Check grants and identity mapping without weakening the fail-closed policy. |
| `409 IDEMPOTENCY_CONFLICT` | Do not reuse an idempotency key for a different canonical request. Generate a new key for a genuinely new operation. |
| `409 DOCUMENT_CONTENT_CONFLICT` | PDF content is immutable. Use the original bytes for a retry or register a new document record. |
| `409 STALE_APPLICATION_STATUS` or `STALE_DOCUMENT_STATUS` | Refresh current state and retry only if the requested transition is still valid. Do not bypass optimistic concurrency. |
| `409 WORKFLOW_NOT_RELEASABLE` | Only a deferred workflow, or one already pending/dispatching/retrying/started, can accept a release retry. Inspect the response's workflow state. |
| Database authentication or schema validation fails | Rerun `setup-local-db.sh` with the intended runtime credentials and schema profile; never switch the service to the schema-owner account. |
| MicroTx dispatch stays retryable | Check the saved workflow name/version, endpoint, OAuth client, token endpoint, and the live-integration limitations in [MICROTX_INTEGRATION.md](MICROTX_INTEGRATION.md). |

Use the error `correlationId`, application ID, and trace ID when investigating logs and telemetry. Never include access tokens, credentials, raw PDF content, or other sensitive values in diagnostic output.
