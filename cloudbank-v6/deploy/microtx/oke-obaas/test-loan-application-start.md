# Create and start a Loan Application through the local APIs

This procedure obtains an OAuth user token, creates one synthetic loan
application, uploads its required PDF, releases that specific application, and
verifies that Loan Application Service has started `cloudbank-loan-origination`
version `1` in MicroTx.

The procedure creates durable local database data. It uses only synthetic
values. Do not paste authorization codes, passwords, client secrets, access
tokens, refresh tokens, or complete callback URLs into source control, chat,
or tickets.

## Prerequisites

- CloudBank Azn is running on port `8080`.
- Loan Application Service is running on port `8081`.
- MicroTx is running and `cloudbank-loan-origination` version `1` has been
  validated and deployed. From
  `src/workflows/cloudbank-loan-origination`, `./deploy.sh` accepts only
  `workflow-v1.json` or `workflow-v1-obaas.json`, supplied explicitly.
- Loan Application Service was started or recreated after setting
  `WORKFLOW_MODE=microtx`, `MICROTX_WORKFLOW_NAME=cloudbank-loan-origination`,
  and a reachable `MICROTX_WORKFLOW_URL`. Workflow version `1` is fixed in the
  application and cannot be overridden by an environment variable.
  `WORKFLOW_MODE=fake` does not contact MicroTx.
- `curl`, `jq`, and `openssl` are installed.
- The local `.env` file contains:
  - `AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD` for `obaas-admin`;
  - `AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET` for `cloudbank-client`.

Use the lab owner, `obaas-admin`, for this test. The OKE services deployment
provisions its application `ADMIN` grant automatically. For an older
installation, complete the [lab owner bootstrap](../../obaas/lab-owner-runbook.md)
first. Do not use the MicroTx worker client or its secret for this flow.

## 1. Set local endpoints

```zsh
export AUTH_SERVER_URL='http://127.0.0.1:8080'
export LOAN_BASE_URL='http://127.0.0.1:8081'
export CLIENT_ID='cloudbank-client'
export REDIRECT_URI='http://127.0.0.1:8080/login/oauth2/code/cloudbank-client'
```

Check that the services are available:

```zsh
curl --fail --silent \
  "$AUTH_SERVER_URL/.well-known/oauth-authorization-server" |
  jq -r '.issuer'

curl --fail --silent "$LOAN_BASE_URL/actuator/health" |
  jq -r '.status'
```

The Loan Application Service health result must be `UP`.

## 2. Generate PKCE values

Use a new PKCE verifier and challenge for every login attempt. Do not reuse a
verifier, authorization URL, or authorization code from a previous attempt.
If a token exchange returns HTTP `400`, restart from this step in the same
terminal; authorization codes are short-lived and can be used only once.

```zsh
unset ACCESS_TOKEN AUTHORIZATION_CODE CLIENT_SECRET PKCE_VERIFIER PKCE_CHALLENGE

export PKCE_VERIFIER="$(
  openssl rand -base64 64 | tr '+/' '-_' | tr -d '=\n'
)"

export PKCE_CHALLENGE="$(
  printf '%s' "$PKCE_VERIFIER" |
  openssl dgst -binary -sha256 |
  openssl base64 |
  tr '+/' '-_' |
  tr -d '=\n'
)"
```

Keep this terminal open. The verifier is required in step 4.

## 3. Sign in as `obaas-admin`

Print the authorization URL:

```zsh
printf '%s\n' \
  "$AUTH_SERVER_URL/oauth2/authorize?response_type=code&client_id=$CLIENT_ID&redirect_uri=http%3A%2F%2F127.0.0.1%3A8080%2Flogin%2Foauth2%2Fcode%2Fcloudbank-client&scope=openid%20cloudbank.read%20cloudbank.write&code_challenge=$PKCE_CHALLENGE&code_challenge_method=S256"
```

1. Open the printed URL in a private browser window.
2. Log in with username `obaas-admin` and the value of
   `AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD` from `.env`.
3. The browser may display a Whitelabel `404` at the callback. This is expected
   because this local test has no BFF handler.
4. The address bar must contain `?code=<code>&state=<state>`.
5. Copy only the value of `code` and immediately continue to step 4 in the
   same terminal. It is short-lived and single-use.

## 4. Exchange the authorization code for a user token

At the first prompt, paste the code from step 3. At the second prompt, paste
the value of `AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET` from `.env`.

```zsh
read -r -s 'AUTHORIZATION_CODE?Authorization code: '; echo
read -r -s 'CLIENT_SECRET?cloudbank-client secret: '; echo

export ACCESS_TOKEN="$(
  curl --silent --show-error --fail \
    --user "$CLIENT_ID:$CLIENT_SECRET" \
    --request POST "$AUTH_SERVER_URL/oauth2/token" \
    --data-urlencode 'grant_type=authorization_code' \
    --data-urlencode "code=$AUTHORIZATION_CODE" \
    --data-urlencode "redirect_uri=$REDIRECT_URI" \
    --data-urlencode "code_verifier=$PKCE_VERIFIER" |
  jq -r '.access_token'
)"

unset AUTHORIZATION_CODE CLIENT_SECRET PKCE_VERIFIER PKCE_CHALLENGE

[[ -n "$ACCESS_TOKEN" && "$ACCESS_TOKEN" != 'null' ]] &&
  echo 'Applicant user token obtained.'
```

## 5. Create a deferred synthetic application

The unique values below avoid idempotency and synthetic-data collisions.
`DEFERRED` stores the workflow-start request without calling MicroTx yet.

```zsh
export RUN_ID="$(date +%s)-$RANDOM"
export IDEMPOTENCY_KEY="manual-loan-$RUN_ID"

CREATE_RESPONSE="$(
  curl --silent --show-error --fail-with-body \
    --request POST \
    --url "$LOAN_BASE_URL/api/v1/loan-applications" \
    --header "Authorization: Bearer $ACCESS_TOKEN" \
    --header 'Content-Type: application/json' \
    --header "Idempotency-Key: $IDEMPOTENCY_KEY" \
    --data "$(jq -n --arg run "$RUN_ID" '
      {
        scenarioId: ("MANUAL-CURL-" + $run),
        scenarioName: "Manual curl synthetic intake",
        applicant: {
          displayName: "Synthetic Applicant",
          phoneToken: ("synthetic-phone-" + $run),
          emailToken: ("synthetic-email-" + $run),
          ageBand: "35-44"
        },
        loan: {
          requestedAmount: 5000.00,
          requestedTermMonths: 24,
          purposeCode: "OTHER_CONSUMER_PURPOSE",
          policyVersion: "2026.0"
        },
        documents: [
          {
            documentType: "LOAN_APPLICATION",
            fileName: ("loan-application-" + $run + ".pdf"),
            status: "EXPECTED",
            required: true,
            mediaType: "application/pdf"
          }
        ],
        workflowStartMode: "DEFERRED"
      }
    ')"
)"

printf '%s\n' "$CREATE_RESPONSE" | jq .
export APPLICATION_ID="$(jq -r '.applicationId' <<<"$CREATE_RESPONSE")"
export DOCUMENT_ID="$(jq -r '.documents[] | select(.documentType == "LOAN_APPLICATION") | .documentId' <<<"$CREATE_RESPONSE")"
```

Expected result: HTTP `202` and an application ID similar to `APP-...`.

## 6. Read the created application

```zsh
curl --silent --show-error --fail-with-body \
  --url "$LOAN_BASE_URL/api/v1/loan-applications/$APPLICATION_ID" \
  --header "Authorization: Bearer $ACCESS_TOKEN" |
  jq .
```

At this point, the workflow dispatch status is `DEFERRED`; no execution has
been sent to MicroTx.

## 7. Upload the required PDF before starting the workflow

The created document is intentionally `EXPECTED` until its PDF content has
been uploaded. MicroTx must not be started while a required document remains
in that state: document ingest only extracts `RECEIVED`, `FAILED_RETRYABLE`,
or `EXTRACTED` documents. Starting early produces an empty
`extract_documents.results` response; document review then reports
`MISSING_REQUIRED_DOCUMENT` and `MISSING_REQUIRED_EXTRACTION` and returns
`BLOCKED`.

Use a repository synthetic PDF that matches the declared document type:

```zsh
export PDF_PATH='synthetic_data/customer_packets/app_apr_001_elena_parker/loan_application.pdf'
export DOCUMENT_UPLOAD_IDEMPOTENCY_KEY="manual-document-upload-$RUN_ID"

curl --silent --show-error --fail-with-body \
  --request PUT \
  --url "$LOAN_BASE_URL/api/v1/loan-applications/$APPLICATION_ID/documents/$DOCUMENT_ID/content" \
  --header "Authorization: Bearer $ACCESS_TOKEN" \
  --header 'Content-Type: application/pdf' \
  --header "Idempotency-Key: $DOCUMENT_UPLOAD_IDEMPOTENCY_KEY" \
  --data-binary "@$PDF_PATH" |
  jq .
```

Expected result: the document response has `status: "RECEIVED"`. Reuploading
the identical PDF is safe; different content for the same document ID is
rejected because uploaded document content is immutable.

## 8. Start this application's MicroTx workflow

This is a state-changing operation. It changes the workflow-start request from
`DEFERRED` to `PENDING`. The Loan Application Service outbox dispatcher then
attempts to submit the configured workflow to MicroTx.

Run this only when the MicroTx workflow definition and its downstream services
are ready:

```zsh
curl --silent --show-error --fail-with-body \
  --request POST \
  --url "$LOAN_BASE_URL/api/v1/loan-applications/$APPLICATION_ID/workflow-start" \
  --header "Authorization: Bearer $ACCESS_TOKEN" |
  jq .
```

The immediate HTTP response confirms only that the request was released. The
outbox dispatcher then starts the workflow asynchronously. Repeat the following
command manually until it reports `workflow.dispatchStatus: STARTED` and a
non-empty `workflow.workflowId`:

```zsh
curl --silent --show-error --fail-with-body \
  --url "$LOAN_BASE_URL/api/v1/loan-applications/$APPLICATION_ID" \
  --header "Authorization: Bearer $ACCESS_TOKEN" |
  jq '.workflow'
```

`STARTED` proves that Loan Application Service received a MicroTx workflow ID
for `cloudbank-loan-origination` version `1`. It does not mean that the full
document-extraction, review, and human-task path has completed.

Once `workflow.workflowId` is present, save it and repeat this command manually
to check the actual MicroTx execution status. It deliberately prints only
workflow and task status metadata, not task input or output data that can
include authorization values:

```zsh
export WORKFLOW_ID="$(
  curl --silent --show-error --fail-with-body \
    --url "$LOAN_BASE_URL/api/v1/loan-applications/$APPLICATION_ID" \
    --header "Authorization: Bearer $ACCESS_TOKEN" |
  jq -r '.workflow.workflowId // empty'
)"
[[ -n "$WORKFLOW_ID" ]] || {
  printf '%s\n' 'No MicroTx workflow ID is available yet; rerun the preceding application-status command.' >&2
  exit 1
}

curl --silent --show-error --fail-with-body \
  --url "http://localhost/workflow-server/api/workflow/$WORKFLOW_ID?includeTasks=true" |
  jq '{workflowId, workflowName, status, startTime, endTime,
       tasks: [.tasks[] | {referenceTaskName, taskType, status, startTime, endTime}]}'
```

For this workflow, `RUNNING` with `human_task` in `IN_PROGRESS` means the
automated extraction and review tasks have completed and the workflow is
waiting for a human decision. `COMPLETED`, `FAILED`, or `TERMINATED` is a final
workflow state.

## 9. List applications and clean up the shell

```zsh
curl --silent --show-error --fail-with-body \
  --get \
  --url "$LOAN_BASE_URL/api/v1/loan-applications" \
  --header "Authorization: Bearer $ACCESS_TOKEN" \
  --data-urlencode 'page=0' \
  --data-urlencode 'size=20' |
  jq .

unset ACCESS_TOKEN APPLICATION_ID DOCUMENT_ID CREATE_RESPONSE RUN_ID IDEMPOTENCY_KEY
unset PDF_PATH DOCUMENT_UPLOAD_IDEMPOTENCY_KEY
unset WORKFLOW_ID
unset AUTH_SERVER_URL LOAN_BASE_URL CLIENT_ID REDIRECT_URI
```

## Troubleshooting

| Result | Meaning |
| --- | --- |
| Whitelabel `404` after browser login, with `code=` in the URL | Expected local callback behavior. Continue to step 4. |
| Token exchange returns HTTP `400` | The code expired or was used, the client secret is wrong, or the PKCE verifier comes from another login attempt. Restart at step 2 and use a new browser login. |
| `401` from Loan Application Service | The access token is missing, expired, or invalid. |
| `403` from Loan Application Service | The token lacks the user scope/role, or the caller is not authorized for that application. |
| `409 DATA_CONFLICT` during step 5 | Stop retrying with the same values. Obtain the correlation ID, confirm that the login user is `obaas-admin`, and investigate the service/database constraint. |
| Workflow remains `PENDING`, `IN_PROGRESS`, or becomes `FAILED_RETRYABLE` | Check that the running Loan Application Service has `WORKFLOW_MODE=microtx`, uses workflow version `1`, can reach MicroTx, and has valid workflow and task OAuth credentials. |
| Workflow becomes `FAILED_FINAL` | The workflow configuration or MicroTx request was rejected. Check the service logs and confirm that version `1` was deployed. |
| `review_documents` returns `MISSING_REQUIRED_DOCUMENT` and `MISSING_REQUIRED_EXTRACTION` | A required document was still `EXPECTED` when the workflow started. Upload the PDF so the document becomes `RECEIVED`, then start a new workflow execution; retrying the same execution does not add document content. |
