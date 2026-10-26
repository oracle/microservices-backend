# Decision Service

`decision-service` owns CloudBank's deterministic lending outcomes. It is a
Spring Boot service invoked by `cloudbank-loan-origination` version 1 after
document, policy, and geographic-risk evidence has been gathered.

The service does not call an LLM and does not treat AI output as a decision
fact. It reads only typed relational facts, evaluates the versioned rule
profile, persists the result in `CB_DECISION` with bounded policy citations,
and asks `loan-application-service` to perform the canonical application-state
transition.

## Contract

The protected endpoint is:

```text
POST /internal/api/v1/decisions
Idempotency-Key: decision:initial:<applicationId>:<workflowId>
Authorization: Bearer <service-token>
```

The request carries identifiers and bounded dispositions, not document text,
PDF bytes, applicant details, access tokens, or model output. Supported
decision types are:

- `INITIAL`: returns `APPROVED`, `REJECTED`, or `MANUAL_REVIEW`.
- `MANUAL_FINAL`: accepts only an `UNDERWRITER` completion with an
  `APPROVED` or `REJECTED` outcome and re-applies non-overridable hard rules.

Read endpoints expose the stored, bounded result:

```text
GET /internal/api/v1/decisions/{decisionId}
GET /internal/api/v1/applications/{applicationId}/decisions/latest
```

All endpoints require a JWT issued by `azn-server`, audience `cloudbank-api`,
`token_kind=service`, scope `cloudbank.internal`, and an allow-listed client
ID. The service obtains its own outbound client-credentials token and never
forwards the inbound workflow bearer token.

## Rule profile v1

Rules are evaluated in deterministic precedence order:

1. Hard rejects: DTI above 50%, recent severe delinquency, open bankruptcy,
   or failed payment calculation.
2. Manual review: incomplete/non-clear upstream evidence, missing capacity or
   payment facts, income below the automatic threshold, inconsistent or
   low-confidence income, DTI above 43%, short/variable tenure, and unresolved
   delinquency or bankruptcy context.
3. Approval: all required document, policy, geographic, income, payment, and
   capacity rules pass.

The thresholds and routing follow `CBPL-120`, `CBPL-130`, and `CBPL-150` in
`synthetic_data/policy`. Policy citations are persisted without copying policy
chunk content into the decision response or application logs.

`BLOCKED` remains an operational evidence outcome, not a loan rejection. The
workflow terminates that path for remediation before invoking decisioning.

## Configuration

| Variable | Purpose |
| --- | --- |
| `DECISION_DATASOURCE_URL` | Oracle JDBC URL. |
| `DECISION_DATASOURCE_USERNAME` | Defaults to `CB_DECISION_APP`. |
| `DECISION_DATASOURCE_PASSWORD` | Runtime database credential. |
| `DECISION_SCHEMA` | Defaults to `CLOUDBANK`. |
| `DECISION_CALLER_CLIENT_IDS` | Allow-listed inbound service clients. |
| `DECISION_TOKEN_URI` | `azn-server` token endpoint for outbound calls. |
| `DECISION_CLIENT_ID` / `DECISION_CLIENT_SECRET` | Outbound client credentials. |
| `LOAN_APPLICATION_BASE_URL` | Internal loan-service base URL. |

Compose exposes the service on port `8088`. OBaaS deploys it as the internal
`decision-service:8080` Kubernetes Service with an isolated database Secret
and the ADB wallet mounted read-only.

## Test

```bash
mvn -f src/decision-service/pom.xml test
SERVICE_CLIENT_SECRET='<local service client secret>' src/decision-service/smoke-test.sh
```

The test suite covers approval, hard rejection, incomplete-fact manual
routing, underwriter finalization, idempotent replay, canonical status
transitions, controller authorization, and internal service-token checks. The
smoke test is non-mutating: it verifies health, anonymous rejection, and an
authorized bounded not-found response.
