# Test authenticated access to the MicroTx Workflow API

This local test obtains an OAuth user token from CloudBank Azn and uses it to
list the workflow definitions deployed in MicroTx.

Use it only in the local development environment. Do not paste authorization
codes, passwords, client secrets, access tokens, refresh tokens, or complete
callback URLs into tickets, chat, terminal history, or source control.

## Prerequisites

- CloudBank Azn is running on local port `8080`.
- MicroTx Workflow Server is reachable at
  `http://localhost/workflow-server/api`.
- The local OAuth client `cloudbank-client` is enabled.
- You can sign in as `obaas-admin`. This user has the roles required to read
  workflow metadata.
- `curl`, `jq`, and `openssl` are installed.

The test deliberately uses `127.0.0.1` for the browser authorization request
and callback because the local `cloudbank-client` registration uses this exact
redirect URI. Keep the authorization request and callback on the same host so
that the browser preserves the Azn login session.

## 1. Start with a clean terminal

```zsh
export AUTH_SERVER_URL='http://127.0.0.1:8080'
export CONDUCTOR_SERVER_URL='http://localhost/workflow-server/api'
export CLIENT_ID='cloudbank-client'
export REDIRECT_URI='http://127.0.0.1:8080/login/oauth2/code/cloudbank-client'
```

Verify that Azn is available:

```zsh
curl --fail --silent \
  "$AUTH_SERVER_URL/.well-known/oauth-authorization-server" |
  jq -r '.issuer'
```

## 2. Generate PKCE values

```zsh
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

Keep this terminal open. The `PKCE_VERIFIER` is required for the token
exchange in step 4.

## 3. Authenticate the user in the browser

Print the authorization URL:

```zsh
printf '%s\n' \
  "$AUTH_SERVER_URL/oauth2/authorize?response_type=code&client_id=$CLIENT_ID&redirect_uri=http%3A%2F%2F127.0.0.1%3A8080%2Flogin%2Foauth2%2Fcode%2Fcloudbank-client&scope=openid%20cloudbank.read%20cloudbank.write&code_challenge=$PKCE_CHALLENGE&code_challenge_method=S256"
```

1. Open the printed URL in a private browser window.
2. Sign in as `obaas-admin`.
3. After login, the browser redirects to the registered callback URL.

The callback has no local BFF handler, so the browser may display a Whitelabel
`404` page. This is expected for this manual test. Check the address bar. It
must contain:

```text
http://127.0.0.1:8080/login/oauth2/code/cloudbank-client?code=<code>&state=<state>
```

Copy **only** the value of the `code` parameter. Do not copy or share the full
URL. The authorization code is short-lived and can be used only once.

## 4. Exchange the code for an access token

Run the following in the terminal from step 2. At the first prompt, paste the
authorization code. At the second prompt, paste the value of
`AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET` from the local untracked
`.env` file.

```zsh
read -r -s 'AUTHORIZATION_CODE?Authorization code: '; echo
read -r -s 'CLIENT_SECRET?cloudbank-client secret: '; echo

export USER_ACCESS_TOKEN="$(
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

[[ -n "$USER_ACCESS_TOKEN" && "$USER_ACCESS_TOKEN" != 'null' ]] &&
  echo 'User token obtained.'
```

Do not use the `microtx-workflow-client` secret for this step. It is a worker
client and does not have the metadata-management role required by this API.

## 5. List deployed workflow definitions

```zsh
curl --silent --show-error --fail \
  --header "Authorization: Bearer $USER_ACCESS_TOKEN" \
  "$CONDUCTOR_SERVER_URL/metadata/workflow" |
  jq -r '.[] | [.name, (.version | tostring), (.description // "")] | @tsv'
```

The output contains workflow name, version, and description.

## 6. Clean up the shell

```zsh
unset USER_ACCESS_TOKEN AUTH_SERVER_URL CONDUCTOR_SERVER_URL CLIENT_ID REDIRECT_URI
```

## Expected failures

| Result | Meaning |
| --- | --- |
| `404` after browser login, with `code=` in the address bar | Expected local callback behavior; continue with step 4. |
| `curl: (22)` during token exchange | The code expired, was already used, the client secret is wrong, or the PKCE verifier came from a different login attempt. Restart from step 2. |
| `401` from the Workflow API | The token is absent, expired, or rejected by the configured JWT validation. |
| `403` from the Workflow API | Authentication succeeded, but the token lacks the required MicroTx metadata role. Sign in as `obaas-admin` or `obaas-config`. |
