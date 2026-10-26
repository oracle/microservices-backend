# CloudBank Gateway BFF

Copyright (c) 2026, Oracle and/or its affiliates. Licensed under UPL 1.0.

This Spring Boot service implements authentication/session, the authorized
application list, deferred application creation, individual PDF upload, and
explicit workflow release, and HUMAN manual review from
[the browser API specification](../../docs/ui/minimum-bff-api.md).
The live Vite UI supports creation, upload, and start for a new application in
one page flow. Reopening existing records, workspace composition, additional
document registration remain planned. The Vite development
proxy makes `/bff` available on the same origin.

| Browser endpoint | Behavior |
| --- | --- |
| `GET /bff/auth/login` | Starts authorization-code login with PKCE. |
| `GET /bff/auth/callback` | OIDC callback; checks the signed access token, the existing `obaas-admin` identity, `ROLE_ADMIN`, principal mapping, and read scope. Redirects to `/demo`. |
| `GET /bff/api/v1/session` | Returns the safe profile, session expiry, and session-bound CSRF token. |
| `POST /bff/auth/logout` | Requires CSRF; invalidates the session and clears `CBBFFSESSION`. |
| `GET /bff/api/v1/applications` | Relays the server-held user token to `loan-application-service`; returns only approved list fields. |
| `POST /bff/api/v1/applications` | Requires CSRF, write scope, and `Idempotency-Key`; creates metadata with `DEFERRED` workflow start and `EXPECTED` documents. Returns `202`, safe IDs/correlation, and a browser-relative Location. |
| `PUT /bff/api/v1/applications/{applicationId}/documents/{documentId}/content` | Requires CSRF, write scope, and `Idempotency-Key`; forwards one raw PDF body to its authorized loan-service document ID. Returns stored length, digest, status, and correlation. |
| `POST /bff/api/v1/applications/{applicationId}/workflow-start` | Requires CSRF, write scope, and an empty body; releases the existing loan outbox. Returns `202` and the canonical dispatch summary. |
| `GET /bff/api/v1/manual-review/tasks` | Authorized pending CloudBank v1 HUMAN queue; pagination after filtering. |
| `GET /bff/api/v1/manual-review/tasks/{taskId}` | Rechecks the task, workflow and authorized application; returns bounded details, outcomes and form defaults. |
| `POST /bff/api/v1/manual-review/tasks/{taskId}/resolution` | Requires CSRF, write scope, explicit UNDERWRITER role and `Idempotency-Key`; completes the HUMAN task with server-derived reviewer identity. |

Creation forwards only the documented input fields and rejects extra technical
fields. Amount and term are parsed on the server; optional blank country,
postal code, and policy version become absent values. Loan-service validation
remains authoritative, including its requirement for at least one document
metadata row. Creation accepts metadata only and leaves workflow dispatch deferred.
Retries forward the same logical idempotency key to the loan owner. Downstream
errors are mapped to fixed safe messages; raw response bodies are excluded.

Upload reads at most 25 MiB plus one overflow byte, including requests with no
Content-Length. Empty and oversized bodies return `413`; unsupported media types
return `415`. The loan service owns authorization, durable PDF BLOBs, digest,
and immutable-content handling. Identical retries succeed; different replacement
bytes conflict. The BFF never sends PDFs to MicroTx or performs extraction.
Workflow release calls only the loan-service boundary. Acceptance is scheduling,
not execution completion or a lending outcome. Repeated release reconciles an
already pending, dispatching, retrying, or started outbox without duplicate starts.

The BFF keeps the OAuth client secret and user tokens on the server. Sessions
are in pod memory, so the OKE chart uses one replica and a deployment restart
signs users out. Cookie settings are HttpOnly, SameSite=Lax, Secure by default;
set `BFF_COOKIE_SECURE=false` only for local HTTP port-forward testing.
The BFF access token lasts at most 30 minutes. The session response reports
the earlier of its HTTP-session expiry and token expiry; expired tokens require
a fresh login.
The service exposes only an internal ClusterIP Service. It does not route the
authorization server's `/user/api/v1*` endpoints to the browser.

The OIDC client is registered in `azn-server` only when both
`AZN_AUTHORIZATION_SERVER_BFF_CLIENT_SECRET` and
`AZN_AUTHORIZATION_SERVER_BFF_CLIENT_REDIRECT_URI` are configured. It uses
`cloudbank-bff-client`, the exact callback URI, `openid`, `cloudbank.read`, and `cloudbank.write`,
client-secret basic authentication, and required PKCE. The server's deployed
issuer must equal `BFF_ISSUER_URI`. The browser must reach
`BFF_AUTHORIZATION_URI`; token, JWKS, and UserInfo URIs are cluster-internal.
Deploy the updated authorization server and BFF together, then sign in again
to obtain the write scope; existing read-only sessions cannot create records.

Run the module tests with `mvn -f src/gateway-bff-service/pom.xml test`.
For OKE publication and repeatable deployment, see
[the BFF runbook](../../deploy/obaas/gateway-bff-runbook.md).

## HUMAN manual review

The form submits exactly `decisionOutcome` (`APPROVED` or `REJECTED`),
`reasonCode` (`[A-Z0-9_:-]{3,120}`), and `policySection`
(`CBPL-[0-9]{3}-S[0-9]+`). The BFF rejects unknown fields, verifies the signed
`ROLE_UNDERWRITER` grant, derives `reviewerPrincipalId` from `cb_principal_id`,
and adds `reviewerRole=UNDERWRITER`. Both outcomes use MicroTx task status
`COMPLETED`. Defaults match `complete-manual-review.sh`.

Configure `BFF_MICROTX_BASE_URL` with the full cluster-reachable `/workflow-server/api`
base, `BFF_MICROTX_TOKEN_URI` with the internal token endpoint,
`BFF_MICROTX_CLIENT_ID` (default `microtx-workflow-client`) and
`BFF_MICROTX_CLIENT_SECRET` through a Kubernetes Secret. Client-credentials tokens
are cached/refreshed server-side with scope `microtx.workflow`. The initial
integration reuses the existing MicroTx operator client; browser authorization
is independently enforced by the BFF. Missing MicroTx configuration affects only
review operations, which return a safe `503`.

Every detail/submission verifies task type/reference, actual workflow name/version,
task/workflow application IDs, the loan service's current workflow link, and the
session user's authorized loan read. Only explicitly projected fields leave
the BFF; raw notification/task/workflow input, tokens and history are excluded.
The queue scans at most 1000 notification rows, then paginates the authorized
pending results; exceeding the limit returns `503` instead of partial counts.
Evidence IDs are references only; evidence/AI read composition remains planned.

The single-replica chart serializes same-task writes in the BFF. Session-bound
operation keys reject changed submissions (up to 100 keys/session), and durable
MicroTx completion output reconciles identical retries after browser/process
restarts. A timeout triggers a task read; an unconfirmed completion returns a
retryable error. A conflicting completion or closed task returns `409`. Multi-replica
browser sessions and distributed submission coordination are outside this increment.
`202` confirms HUMAN completion acceptance, not final loan approval. The workflow
refreshes service authorization and runs its deterministic manual-final decision.
