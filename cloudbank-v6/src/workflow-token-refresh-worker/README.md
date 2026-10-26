# Workflow Token Refresh Worker

`workflow-token-refresh-worker` is a Spring Boot MicroTx task worker for the
`refresh_workflow_authorization` task. Version 1 schedules that `SIMPLE`
task immediately after `human_task_manual_review` completes. The worker obtains
a fresh short-lived CloudBank service token from `azn-server` and completes the
task with a masked `workflowTaskAuthorization` output. The workflow's following
`use_refreshed_authorization` task installs that output as the runtime
authorization variable used by later HTTP tasks.

The worker exists because the token injected when the workflow starts may
expire while a HUMAN task waits for reviewer action. It never receives or
stores a client secret in workflow input or output.

## Runtime Flow

```text
MicroTx HUMAN task completes
→ MicroTx queues refresh_workflow_authorization
→ worker polls the task with its MicroTx identity
→ worker requests a cloudbank.internal token from azn-server
→ worker completes the task with workflowTaskAuthorization and its expiry
→ workflow replaces workflow.variables.workflowTaskAuthorization
```

The output shape is:

```json
{
  "workflowTaskAuthorization": "Bearer <fresh-token>",
  "expiresAtEpochSecond": 1787583900
}
```

The workflow definition includes both `workflowTaskAuthorization` and
`Authorization` in `maskedFields`. The token remains sensitive workflow state:
release validation must confirm masking in the execution API, task API,
console, logs, traces, retries, and persisted history. The worker never logs the
token, token response, client secret, or remote response body.

## Identities

The worker uses two isolated OAuth purposes:

| Purpose | Default client | Audience and scope |
| --- | --- | --- |
| Poll and complete MicroTx tasks | `microtx-workflow-client` | `microtx-workflow`, `microtx.workflow`, Conductor worker role |
| Produce the refreshed CloudBank task token | `cloudbank-service-client` | `cloudbank-api`, `cloudbank.internal`, service token |

Compose maps their secrets from the existing ignored `.env` entries:

```text
AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET
AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET
```

No new `.env` entry is required, and `run-compose.sh` does not copy a value from
the caller's shell into a new configuration key.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `WORKFLOW_MODE` | `fake` | Poll only when set to `microtx`; otherwise remain healthy and idle. |
| `MICROTX_WORKFLOW_URL` | empty | Container-reachable Workflow Server base URL, immediately before `/api` or including `/api`. |
| `WORKFLOW_TOKEN_REFRESH_TASK_TYPE` | `refresh_workflow_authorization` | MicroTx task definition and queue name. |
| `WORKFLOW_TOKEN_REFRESH_WORKER_ID` | `cloudbank-workflow-token-refresh-worker` | Stable worker identifier sent while polling and completing. |
| `WORKFLOW_TOKEN_REFRESH_POLL_DELAY_MS` | `1000` | Delay between polls. |
| `WORKFLOW_TOKEN_REFRESH_MICROTX_TOKEN_URI` | empty | Token endpoint for the MicroTx worker identity. |
| `WORKFLOW_TOKEN_REFRESH_MICROTX_CLIENT_ID` | `microtx-workflow-client` | MicroTx polling/completion client. |
| `WORKFLOW_TOKEN_REFRESH_MICROTX_CLIENT_SECRET` | empty | Secret for the MicroTx client; required in `microtx` mode. |
| `WORKFLOW_TOKEN_REFRESH_MICROTX_SCOPE` | `microtx.workflow` | MicroTx API scope. |
| `WORKFLOW_TOKEN_REFRESH_TASK_TOKEN_URI` | empty | Token endpoint used to obtain the refreshed CloudBank token. |
| `WORKFLOW_TOKEN_REFRESH_TASK_CLIENT_ID` | `cloudbank-service-client` | CloudBank service-token client. |
| `WORKFLOW_TOKEN_REFRESH_TASK_CLIENT_SECRET` | empty | Secret for the CloudBank client; required in `microtx` mode. |
| `WORKFLOW_TOKEN_REFRESH_TASK_SCOPE` | `cloudbank.internal` | Scope returned in the refreshed token. |

When `WORKFLOW_MODE=microtx`, startup fails if a URL, client ID, secret, or
scope required by either identity is missing. OAuth tokens are cached only in
memory; the CloudBank task token cache is invalidated for every claimed refresh
task so the task always receives a newly issued token.

## Compose

`./run-compose.sh up` builds and starts the worker on port `8087`. In the normal
`fake` Compose mode it remains idle. With `WORKFLOW_MODE=microtx`, ensure that
`MICROTX_WORKFLOW_URL` is reachable from inside the container; for the local
Rancher Desktop port-forward setup this is typically:

```dotenv
MICROTX_WORKFLOW_URL=http://host.rancher-desktop.internal:9010/workflow-server
```

The workflow and both task definitions must then be deployed with:

```bash
MICROTX_DEPLOY_AUTH_MODE=operator \
  ./src/workflows/cloudbank-loan-origination/deploy.sh \
  ./src/workflows/cloudbank-loan-origination/workflow-v1.json
```

## Tests

```bash
mvn -f src/workflow-token-refresh-worker/pom.xml test
curl --silent --show-error --fail http://127.0.0.1:8087/actuator/health
```

The worker reports safe failure codes to MicroTx. A failed token exchange marks
the task `FAILED`, allowing the task definition's bounded retry policy to run;
tokens and authorization-server response bodies are not included in the
failure reason.
