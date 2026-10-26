# CloudBank azn-server

`azn-server` is the CloudBank Spring Authorization Server. It issues OAuth2 access tokens, publishes OIDC/OAuth metadata and JWKS endpoints, and manages the demo user repository stored in Oracle Database.

## What It Provides

| Area | Details |
| --- | --- |
| OAuth2/OIDC | Publishes authorization metadata, JWKS, and token endpoints using Spring Authorization Server. |
| JWT signing | Signs access tokens with either mounted persistent RSA keys or process-local generated keys for development/tests. |
| User repository | Stores users in `USER_REPO.USERS`; passwords and one-time passwords are stored as PBKDF2 hashes. |
| Bootstrap users | Creates missing demo users and reconciles the demo administrator's required roles on startup when `azn.bootstrap-users.enabled=true`, which is the default. |
| Admin API | Provides an internal basic-auth API under `/user/api/v1` for user management and password reset. |
| CloudBank integration | Supplies JWTs that APISIX and the CloudBank resource services validate. |

The shared password encoder uses Spring Security's PBKDF2-HMAC-SHA-256 preset with a 16-byte random salt,
310,000 iterations, a 256-bit derived key, hexadecimal encoding, and no application pepper.

CloudBank access tokens use the configured stable issuer, include `aud=cloudbank-api`, identify the OAuth client, distinguish user and service tokens with `token_kind`, and include signed `roles` and `cb_principal_id` claims for authenticated users. The dedicated `microtx-workflow-client` instead receives `aud=microtx-workflow`, scope `microtx.workflow`, and the `microtx-conductor-user` and `microtx-conductor-worker` roles required by the secured MicroTx Workflow API.

Authorization-server endpoints and access requirements:

| Endpoint | Access |
| --- | --- |
| `GET /.well-known/oauth-authorization-server` | Anonymous OAuth2 metadata. |
| `GET /.well-known/openid-configuration` | Anonymous OIDC metadata. |
| `GET /oauth2/jwks` | Anonymous public signing keys. |
| `POST /oauth2/token` | OAuth client authentication. |
| `/oauth2/authorize` | Authenticated browser user. |
| `GET /userinfo` | Bearer access token. |
| `GET /login` | Browser login page. |

Internal user-management endpoints:

```text
GET    /user/api/v1/ping
GET    /user/api/v1/pinguser
GET    /user/api/v1/pingadmin
GET    /user/api/v1/pingceditor
GET    /user/api/v1/connect
GET    /user/api/v1/findUser
POST   /user/api/v1/createUser
PUT    /user/api/v1/updatePassword
PUT    /user/api/v1/changeRole
PUT    /user/api/v1/changeEmail
DELETE /user/api/v1/deleteUsername
DELETE /user/api/v1/deleteId
GET    /user/api/v1/forgot
POST   /user/api/v1/forgot
PUT    /user/api/v1/forgot
```

Do not expose `/user/api/v1*` publicly. It is intended for cluster-internal or administrative access only.

## Runtime Configuration

`azn-server` is a Java 25 Spring Boot application. It uses Oracle UCP for runtime database connections and Liquibase for schema bootstrap.

The runtime database user is normally the least-privilege `USER_REPO_APP` account. Liquibase connects with a privileged/admin account, creates the locked `USER_REPO` schema owner and `USER_REPO_APP` runtime user, and provisions the `USERS` table and related database objects from `src/main/resources/db/changelog`.

Important environment variables:

| Variable | Purpose |
| --- | --- |
| `AZN_DATASOURCE_URL` | JDBC URL for runtime `USER_REPO_APP` connections. Falls back to `SPRING_DATASOURCE_URL`. |
| `AZN_USER_REPO_USERNAME` | Least-privilege runtime username. Defaults to `USER_REPO_APP`. |
| `AZN_USER_REPO_PASSWORD` | Runtime-user password. Required for normal startup. |
| `AZN_USER_REPO_OWNER_PASSWORD` | Locked schema-owner password used only by Liquibase provisioning. |
| `AZN_LIQUIBASE_URL` | Liquibase JDBC URL. Falls back through Liquibase/Spring datasource variables. |
| `AZN_LIQUIBASE_USERNAME` | Privileged Liquibase username. |
| `AZN_LIQUIBASE_PASSWORD` | Privileged Liquibase password. |
| `RUN_LIQUIBASE` | Enables Liquibase. Defaults to `true`. |
| `AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD` | Initial password for `obaas-admin`. |
| `AZN_BOOTSTRAP_USERS_USER_PASSWORD` | Initial password for `obaas-user` and `obaas-config`. |
| `OBAAS_ADMIN_PASSWORD` | Backward-compatible alias for the administrator bootstrap password. |
| `OBAAS_USER_PASSWORD` | Backward-compatible alias for the user bootstrap password. |
| `AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_ENABLED` | Enables the local in-memory OAuth clients. Defaults to `false`. |
| `AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_ID` | Default OAuth client id. Defaults to `cloudbank-client`. |
| `AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET` | Secret for the authorization-code/PKCE Backend for Frontend (BFF) client. Required when local clients are enabled. |
| `AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET` | Secret for the `cloudbank-service-client` client-credentials client. |
| `AZN_AUTHORIZATION_SERVER_DOCUMENT_INGEST_CLIENT_ID` | Document-ingest client id. Defaults to `cloudbank-document-ingest-client`. |
| `AZN_AUTHORIZATION_SERVER_DOCUMENT_INGEST_CLIENT_SECRET` | Secret for the `cloudbank-document-ingest-client` client-credentials client. |
| `AZN_AUTHORIZATION_SERVER_DOCUMENT_INGEST_CLIENT_SCOPES` | Document-ingest client scopes. Defaults to `cloudbank.internal`. |
| `AZN_AUTHORIZATION_SERVER_DOCUMENT_REVIEW_CLIENT_ID` | Document-review client id. Defaults to `cloudbank-document-review-client`. |
| `AZN_AUTHORIZATION_SERVER_DOCUMENT_REVIEW_CLIENT_SECRET` | Secret for the `cloudbank-document-review-client` client-credentials client. |
| `AZN_AUTHORIZATION_SERVER_DOCUMENT_REVIEW_CLIENT_SCOPES` | Document-review client scopes. Defaults to `cloudbank.internal`. |
| `AZN_AUTHORIZATION_SERVER_AI_AGENT_CLIENT_ID` | AI-agent client id. Defaults to `cloudbank-ai-agent-client`. |
| `AZN_AUTHORIZATION_SERVER_AI_AGENT_CLIENT_SECRET` | Secret for the AI-agent client-credentials client. |
| `AZN_AUTHORIZATION_SERVER_AI_AGENT_CLIENT_SCOPES` | AI-agent client scopes. Defaults to `cloudbank.internal`. |
| `AZN_AUTHORIZATION_SERVER_TEST_CLIENT_SECRET` | Secret for `cloudbank-test-client`, if enabled. |
| `AZN_AUTHORIZATION_SERVER_ADMIN_CLIENT_SECRET` | Secret for `cloudbank-admin-client`, if enabled. |
| `AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_ID` | MicroTx client id. Defaults to `microtx-workflow-client`. |
| `AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET` | Secret for the MicroTx client-credentials client. |
| `AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SCOPES` | MicroTx scopes. Defaults to `microtx.workflow`. |
| `AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_ROLES` | MicroTx roles claim. Defaults to `microtx-conductor-user,microtx-conductor-worker`. |
| `AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_AUDIENCE` | MicroTx audience. Defaults to `microtx-workflow`. |
| `AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_ID` | Optional MicroTx/OTMM Console OIDC client id. Defaults to `microtx-console-client`. |
| `AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_SECRET` | Secret for the optional MicroTx/OTMM Console authorization-code client. |
| `AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_SCOPES` | Comma-delimited Console scopes. Defaults to `openid,cloudbank.read,cloudbank.write`. |
| `AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_REDIRECT_URI` | Required Console authorization-code redirect URI; enables Console registration when paired with a secret. |
| `AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_POST_LOGOUT_REDIRECT_URI` | Optional registered post-logout redirect URI for the Console. |
| `AZN_AUTHORIZATION_SERVER_SIGNING_KEY_PRIVATE_KEY_PATH` | Path to a mounted PKCS#8 PEM RSA private key. |
| `AZN_AUTHORIZATION_SERVER_SIGNING_KEY_PUBLIC_KEY_PATH` | Path to a mounted X.509 PEM RSA public key. |
| `AZN_AUTHORIZATION_SERVER_SIGNING_KEY_KEY_ID` | Stable key id published in JWKS and JWT headers. |
| `AZN_ISSUER_URI` | Stable externally visible issuer used in metadata and token validation. |
| `AZN_AUDIENCE` | Resource-server audience. Defaults to `cloudbank-api`. |
| `AZN_PERSISTENT_SIGNING_KEY_REQUIRED` | Fail startup when mounted signing keys are absent. Set to `true` in deployed environments. |
| `EUREKA_CLIENT_ENABLED` | Enables Eureka registration/discovery. Defaults to `false` for local runs and tests. |

If signing-key paths are not configured, the service generates process-local RSA keys on startup. That is acceptable for tests and short local runs, but not for a deployment where tokens must remain verifiable after restarts or rolling updates.

Bootstrap users created when missing:

| User | Roles |
| --- | --- |
| `obaas-admin` | `ROLE_ADMIN,ROLE_CONFIG_EDITOR,ROLE_USER,ROLE_UNDERWRITER` |
| `obaas-config` | `ROLE_CONFIG_EDITOR,ROLE_USER` |
| `obaas-user` | `ROLE_APPLICANT,ROLE_USER` |

Supported CloudBank roles also include `ROLE_LOAN_OFFICER`, `ROLE_UNDERWRITER`, `ROLE_AUDITOR`, and `ROLE_OPERATOR`. OAuth clients constrain scopes; signed roles determine business permissions in resource services.

The enabled demo bootstrap ensures the four administrator roles above on both
clean installation and later startup. Existing accounts receive only missing
required grants; existing password hashes, principal IDs, OTP hashes and extra
roles are preserved. Once the baseline is present, subsequent startup performs
no user update. This prepares `obaas-admin` for BFF HUMAN-task completion without
a manual role-change step. Role hierarchy remains unchanged: ADMIN alone does
not imply UNDERWRITER. Disable `azn.bootstrap-users.enabled` to manage accounts
and grants entirely outside the demo bootstrap.

After upgrading an existing deployment, obtain a fresh login at both the BFF and
authorization server (a private browser window suffices); older signed tokens
and existing authorization-server login sessions retain their earlier roles.

Passwords accepted by the user API must be at least 12 characters and include an uppercase letter, lowercase letter, number, and one of `?`, `!`, `$`, `%`, `^`, `*`, `-`, or `_`.

## Local Development

The recommended repository-level workflow starts Oracle, provisions both
CloudBank database areas, and launches all three services:

```bash
./run-compose.sh up
```

Run that command from the repository root. See the
[root README](../../README.md) for the required follow-up `verify` command,
stack lifecycle, persistence, reset, and generated-secret details. The Compose
stack mounts a persistent local signing key; the standalone helper below
remains available when running against an existing host database.
Compose defaults to the unseeded `full-demo` schema profile; select `runtime`
during initial configuration for service-only development.

For an interactive local start, invoke the helper from either the repository
root or `src/azn-server`:

```bash
src/azn-server/run-locally.sh
```

When already in `src/azn-server`, use `./run-locally.sh`. The helper resolves
its module directory before starting Maven, so its behavior does not depend on
the caller's working directory.

The helper reads the repository-root `.env` created by `run-compose.sh` when it is present. It derives the JDBC URL, Liquibase user, and Liquibase password from `ORACLE_HOST_PORT`, `ORACLE_SERVICE_NAME`, `ORACLE_ADMIN_USERNAME`, and `ORACLE_PASSWORD`, and reuses the AZN passwords and OAuth client secrets stored there. Explicitly exported `AZN_*` variables take precedence. Without `.env`, it defaults to `jdbc:oracle:thin:@//localhost:1521/freepdb1` and the `SYSTEM` Liquibase user. It silently prompts for any remaining passwords and OAuth client secrets. Secrets are not accepted as command-line arguments and are not written to disk.

On a clean database, Liquibase creates the locked `USER_REPO` schema owner, the least-privilege `USER_REPO_APP` runtime user, repository objects, and bootstrap users. The owner and runtime passwords must be different.

### Autonomous Database Serverless with a wallet

For an interactive ADB-S start, use the wallet wrapper:

```bash
src/azn-server/run-adb-locally.sh
```

It accepts either a downloaded wallet ZIP or an already extracted wallet directory, displays the service aliases from `tnsnames.ora`, and prompts only for missing values. When the repository-root ignored `.env` file is present, it reads `AZN_ADB_WALLET_PATH`, `AZN_ADB_TNS_ALIAS`, `AZN_LIQUIBASE_PASSWORD` (the ADB `ADMIN` password), `AZN_USER_REPO_OWNER_PASSWORD`, and `AZN_USER_REPO_PASSWORD`. Explicitly exported values take precedence over `.env`. It does not use `ORACLE_PASSWORD` as an ADB-password fallback. ZIP wallets are extracted with restrictive permissions beneath the ignored `.cloudbank-local/adb-wallets/` directory. `TNS_ADMIN` must name the extracted directory, not the ZIP archive. The wrapper validates that new `USER_REPO` passwords meet ADB's 12-to-30-character requirement, then prints the resolved wallet, alias, URLs, usernames, and each secret's source before requesting a `y`/`yes` confirmation. Secret values remain masked. Non-interactive runs do not pause for confirmation and still fail when required values are missing.

For CI or another non-interactive start, export every required secret before invoking the helper:

```bash
export AZN_DATASOURCE_URL='jdbc:oracle:thin:@//<host>:<port>/<service>'
export AZN_USER_REPO_PASSWORD='<user-repo-password>'
export AZN_USER_REPO_OWNER_PASSWORD='<different-owner-password>'

export AZN_LIQUIBASE_URL="$AZN_DATASOURCE_URL"
export AZN_LIQUIBASE_USERNAME='<admin-or-system-user>'
export AZN_LIQUIBASE_PASSWORD='<admin-or-system-password>'

export AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD='<admin-password>'
export AZN_BOOTSTRAP_USERS_USER_PASSWORD='<user-password>'

export AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_ENABLED=true
export AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_ID='cloudbank-client'
export AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET='<browser-client-secret>'
export AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET='<service-client-secret>'
export AZN_AUTHORIZATION_SERVER_DOCUMENT_INGEST_CLIENT_SECRET='<document-ingest-client-secret>'
export AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET='<microtx-client-secret>'

./run-locally.sh
```

The underlying Maven command, when the complete environment is already configured, is:

```bash
mvn -f src/azn-server/pom.xml spring-boot:run
```

The service listens on port `8080` by default.

Verify authorization metadata and keys:

```bash
curl -s http://localhost:8080/.well-known/oauth-authorization-server
curl -s http://localhost:8080/.well-known/openid-configuration
curl -s http://localhost:8080/oauth2/jwks
```

`cloudbank-client` is the browser-facing BFF client. It supports authorization code with PKCE and refresh tokens, but deliberately does not support `client_credentials`. Request machine-to-machine tokens with the separate service client:

```bash
export CLIENT_ID='cloudbank-service-client'
export CLIENT_SECRET='<service-client-secret>'

curl -s -u "$CLIENT_ID:$CLIENT_SECRET" \
  -X POST http://localhost:8080/oauth2/token \
  -d grant_type=client_credentials \
  -d scope=cloudbank.internal
```

Request a token for the secured MicroTx Workflow API with the separate identity:

```bash
export CLIENT_ID='microtx-workflow-client'
export CLIENT_SECRET='<microtx-client-secret>'

curl -s -u "$CLIENT_ID:$CLIENT_SECRET" \
  -X POST http://localhost:8080/oauth2/token \
  -d grant_type=client_credentials \
  -d scope=microtx.workflow
```

This token is only for MicroTx. Its `aud=microtx-workflow` token must not be forwarded to CloudBank resource services, which require `aud=cloudbank-api`.

Basic user API checks:

```bash
curl -i http://localhost:8080/user/api/v1/ping

curl -i -u "obaas-admin:<admin-password>" \
  http://localhost:8080/user/api/v1/connect

curl -i -u "obaas-admin:<admin-password>" \
  'http://localhost:8080/user/api/v1/findUser?username=obaas'
```

Create a user:

```bash
curl -i -u "obaas-admin:<admin-password>" \
  -H 'Content-Type: application/json' \
  -X POST http://localhost:8080/user/api/v1/createUser \
  -d '{
    "username": "demo-user",
    "password": "StrongPass123!",
    "roles": "ROLE_USER",
    "email": "demo-user@example.com"
  }'
```

Change a role or email:

```bash
curl -i -u "obaas-admin:<admin-password>" \
  -H 'Content-Type: application/json' \
  -X PUT http://localhost:8080/user/api/v1/changeRole \
  -d '{"username":"demo-user","roles":"ROLE_CONFIG_EDITOR,ROLE_USER"}'

curl -i -u "obaas-admin:<admin-password>" \
  -H 'Content-Type: application/json' \
  -X PUT http://localhost:8080/user/api/v1/changeEmail \
  -d '{"username":"demo-user","email":"demo-user@example.com"}'
```

Delete a user:

```bash
curl -i -u "obaas-admin:<admin-password>" \
  -X DELETE 'http://localhost:8080/user/api/v1/deleteUsername?username=demo-user'
```

## Password Reset Flow

The password reset API is admin-assisted. It does not send email or SMS, and it does not expose one-time passwords in responses.

Find a user by username or email:

```bash
curl -i -u "obaas-admin:<admin-password>" \
  'http://localhost:8080/user/api/v1/forgot?username=demo-user'
```

Store a one-time password hash:

```bash
curl -i -u "obaas-admin:<admin-password>" \
  -H 'Content-Type: application/json' \
  -X POST http://localhost:8080/user/api/v1/forgot \
  -d '{"username":"demo-user","otp":"123456"}'
```

Reset the password with the one-time password:

```bash
curl -i -u "obaas-admin:<admin-password>" \
  -H 'Content-Type: application/json' \
  -X PUT http://localhost:8080/user/api/v1/forgot \
  -d '{
    "username": "demo-user",
    "otp": "123456",
    "password": "ResetPass123!"
  }'
```

## Running Instance Smoke Test

For the OBaaS deployment, image publication, Secret contract, and in-cluster
Workflow Server smoke-test procedure, see the [OBaaS azn-server deployment
runbook](../../deploy/obaas/azn-server-runbook.md).

`smoke-test.sh` performs read-only checks against a running authorization server; it does not start or call any downstream service. It verifies the public Actuator surface, OAuth/OIDC metadata, an RSA signing key in JWKS, anonymous and protected user API behavior, administrator roles and secret-free user lookup, and every active machine-token contract. Each issued JWT is cryptographically verified against the server's published JWKS before its claims are checked. When the optional MicroTx Console OIDC client is configured, it also verifies that the client accepts an authorization-code request with PKCE. When bootstrap-user credentials are available, it verifies that the user role cannot administer or edit configuration. Its Basic-authentication checks exercise internal administrative endpoints; `/user/api/v1*` must remain inaccessible through the public gateway.

The machine-token matrix reflects the current service model:

| Service | OAuth identity tested | Contract |
| --- | --- | --- |
| Loan application | `cloudbank-service-client` for workflow tasks; `microtx-workflow-client` for the Workflow API | The task token has the CloudBank internal-service contract; the Workflow API token has isolated `aud=microtx-workflow`, `scope=microtx.workflow`, and MicroTx conductor roles. |
| Document ingest | `cloudbank-document-ingest-client` | Dedicated identity with the CloudBank internal-service contract. |
| Document review | `cloudbank-document-review-client` | Dedicated identity with the CloudBank internal-service contract. |
| AI agent | `cloudbank-ai-agent-client` | Dedicated identity used to retrieve bounded downstream evidence. |
| Geographic risk | `cloudbank-service-client` | Shared internal caller: `aud=cloudbank-api`, `scope=cloudbank.internal`, `token_kind=service`, no roles. |
| Policy retrieval | `cloudbank-service-client` | Shared internal caller: `aud=cloudbank-api`, `scope=cloudbank.internal`, `token_kind=service`, no user roles. The policy service applies its bounded workflow visibility rather than deriving a user role from this token. |

From `src/azn-server`:

```bash
./smoke-test.sh
```

Each run is a grouped terminal report: Platform and OIDC, Internal access controls, Service-token contracts, and Security rejection checks. It starts with the target URL, active client identities, and whether optional bootstrap-user role boundaries are enabled. It performs a separate named service block for loan application, document ingest, document review, geographic risk, policy retrieval, and the loan application's MicroTx Workflow API call.

Every HTTP check prints a shell-escaped, redacted `CURL:` line immediately before its result so operators can identify the precise method, endpoint, headers, and form fields under test. Basic-authentication commands show the user or client ID but replace the credential with `<redacted>`; the real request continues to send its credential through curl's stdin configuration. OAuth authorization-server discovery displays the issuer; authorization, token, JWKS, introspection, and revocation URLs; grants; client-authentication methods; PKCE, mTLS, and DPoP capabilities. The separate OIDC summary displays userinfo and logout/end-session URLs, scopes, subject types, and ID-token signing algorithms without repeating OAuth metadata. Successful machine-token blocks display safe decoded claims: signing key ID, issuer, audience, scope, roles, client ID, token kind, and expiry. Failures remain inline and state the failed request, expected and actual HTTP status, or failed token validation. The final result shows passed and failed totals. Passwords, client secrets, raw JWTs, and token signatures are never displayed.

The script safely reads the repository-root ignored `.env` created by `run-compose.sh` when it is present. It uses its `AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD`, `AZN_BOOTSTRAP_USERS_USER_PASSWORD`, Browser/BFF, shared-service, document-ingest, document-review, AI-agent, MicroTx Workflow, and optional MicroTx Console OAuth entries as defaults. Explicitly exported secrets take precedence, which supports an ADB or other external authorization-server instance.

Before running any checks, the script prompts only for values not provided through the environment or local `.env`: the authorization-server base URL, administrator credentials, shared-service, document-ingest, document-review, MicroTx, and browser-client credentials. Defaults are `http://127.0.0.1:8080`, `cloudbank-service-client`, the two documented client IDs, `cloudbank.internal`, and `cloudbank-client`. Passwords and client secrets use silent input, are not accepted as command-line arguments, and are never printed.

For repository automation, run `./smoke-test.sh --non-interactive`. It reads
`BASE_URL`, `ADMIN_USERNAME`, `ADMIN_PASSWORD`, `SERVICE_CLIENT_ID`,
`SERVICE_CLIENT_SECRET`, `SERVICE_SCOPE`, `DOCUMENT_INGEST_CLIENT_ID`,
`DOCUMENT_INGEST_CLIENT_SECRET`, `DOCUMENT_INGEST_SCOPE`,
`DOCUMENT_REVIEW_CLIENT_ID`, `DOCUMENT_REVIEW_CLIENT_SECRET`,
`DOCUMENT_REVIEW_SCOPE`, `AI_AGENT_CLIENT_ID`, `AI_AGENT_CLIENT_SECRET`,
`AI_AGENT_SCOPE`, `BROWSER_CLIENT_ID`, `BROWSER_CLIENT_SECRET`,
`MICROTX_CLIENT_ID`, `MICROTX_CLIENT_SECRET`, `MICROTX_SCOPE`,
`MICROTX_CONSOLE_CLIENT_ID`, `MICROTX_CONSOLE_CLIENT_SECRET`,
`MICROTX_CONSOLE_SCOPE`, `MICROTX_CONSOLE_REDIRECT_URI`, `USER_USERNAME`, and
`USER_PASSWORD` from the environment, then fills missing secrets from the
root `.env`. The URL, usernames, client IDs, and scopes retain their interactive
defaults; the six required admin/client secrets must be available from one of those
sources. Bootstrap-user checks run
only when `USER_PASSWORD` is available. Prefer the root `./run-compose.sh
verify` command, which supplies the required values without printing them.

The script requires `curl`, `grep`, `openssl`, and the Java runtime used by
azn-server; it does not create, update,
reset, or delete users, roles, passwords, tokens, or OAuth clients.

Each check prints `PASS` or `FAIL`. The script exits with status `0` when every check passes, `1` when a server check fails, and `2` for invalid usage or missing input.

## Maven Build Context

This module inherits dependency and plugin management from the CloudBank root `pom.xml`. Build it either from the module directory or from the repository root. Copying `azn-server` into a standalone repository requires replacing or reproducing that parent configuration.

From `src/azn-server`:

```bash
mvn -DskipTests compile
mvn -DskipTests package
mvn test
mvn verify
```

From the CloudBank repository root:

```bash
mvn -f src/azn-server/pom.xml -DskipTests compile
mvn -f src/azn-server/pom.xml -DskipTests package
mvn -f src/azn-server/pom.xml test
mvn -f src/azn-server/pom.xml verify
```

## Testing

Build and test commands require JDK 25. The examples below run from `src/azn-server`; from the repository root, add `-f src/azn-server/pom.xml` after `mvn`.

Fast unit, controller, and security tests:

```bash
mvn test -Dtest='*Test,*Tests' -DfailIfNoTests=false
```

Normal module test suite:

```bash
mvn test
```

Oracle-backed integration tests can run explicitly:

```bash
mvn -Dtest='*IT' test
```

Full lifecycle verification runs unit tests and Oracle-backed integration tests through Failsafe:

```bash
mvn verify
```

The integration suite includes:

```text
AuthorizationServerIT
MicroTxAuthorizationServerIT
UserApiOracleIT
UserRepositoryOracleIT
```

Those tests use Testcontainers with `gvenzl/oracle-free:23.26.2-slim-faststart`. Docker, Rancher Desktop, or another compatible container runtime must be running. The first run may take longer while the Oracle image is downloaded.

Runtime smoke testing against a real Oracle Database is intentionally separate from this automated test flow.

The integration tests dynamically configure:

- Oracle JDBC and UCP connection settings.
- Liquibase admin access.
- Separate `USER_REPO` owner and `USER_REPO_APP` runtime credentials.
- Bootstrap users.
- Local OAuth clients.
- Disabled Eureka discovery.

The authorization-server integration test explicitly disables the runtime local-client repository, so exported `AZN_AUTHORIZATION_SERVER_*` client settings do not replace its isolated test client.

The test suite verifies:

- OAuth metadata and JWKS endpoints are public.
- Client-credentials token issuance works.
- Liquibase creates the `USER_REPO.USERS` schema objects.
- Startup creates expected bootstrap users and roles.
- User management enforces roles and validates duplicate/weak-password requests.
- Passwords and one-time passwords are PBKDF2-hashed and not returned by API responses.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Startup fails with missing bootstrap password | Set `AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD` and `AZN_BOOTSTRAP_USERS_USER_PASSWORD`, or disable bootstrap users deliberately. |
| Startup fails before JPA validation | Confirm Liquibase ran successfully and the runtime user can connect as `USER_REPO_APP`. |
| Service token requests fail | Confirm local clients are enabled, `AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET` is set, and the request uses `cloudbank-service-client` with `cloudbank.internal`. |
| MicroTx token requests fail | Confirm local clients are enabled, `AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET` is set, and the request uses `microtx-workflow-client` with `microtx.workflow`. |
| Tokens fail after restart | Use persistent signing keys instead of generated process-local keys. |
| Resource services reject tokens | Verify they point to the correct `/oauth2/jwks` URL and expected issuer. |
| Integration tests hang or fail early | Confirm the container runtime is running and can pull `gvenzl/oracle-free:23.26.2-slim-faststart`. |
