#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

set -uo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly ENV_FILE="$REPOSITORY_ROOT/.env"
readonly DEFAULT_BASE_URL="http://127.0.0.1:8080"
readonly DEFAULT_ADMIN_USERNAME="obaas-admin"
readonly DEFAULT_USER_USERNAME="obaas-user"
readonly DEFAULT_SERVICE_CLIENT_ID="cloudbank-service-client"
readonly DEFAULT_SERVICE_SCOPE="cloudbank.internal"
readonly DEFAULT_DOCUMENT_INGEST_CLIENT_ID="cloudbank-document-ingest-client"
readonly DEFAULT_DOCUMENT_REVIEW_CLIENT_ID="cloudbank-document-review-client"
readonly DEFAULT_AI_AGENT_CLIENT_ID="cloudbank-ai-agent-client"
readonly DEFAULT_DOCUMENT_SERVICE_SCOPE="cloudbank.internal"
readonly DEFAULT_BROWSER_CLIENT_ID="cloudbank-client"
readonly DEFAULT_MICROTX_CLIENT_ID="microtx-workflow-client"
readonly DEFAULT_MICROTX_SCOPE="microtx.workflow"
readonly DEFAULT_MICROTX_CONSOLE_CLIENT_ID="microtx-console-client"
readonly DEFAULT_MICROTX_CONSOLE_SCOPE="openid,cloudbank.read,cloudbank.write"

PASS_COUNT=0
FAIL_COUNT=0
RESPONSE_BODY=""
RESPONSE_STATUS=""
NON_INTERACTIVE=false
BASE_URL="${BASE_URL-}"
ADMIN_USERNAME="${ADMIN_USERNAME-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD-}"
USER_USERNAME="${USER_USERNAME-}"
USER_PASSWORD="${USER_PASSWORD-}"
SERVICE_CLIENT_ID="${SERVICE_CLIENT_ID-}"
SERVICE_CLIENT_SECRET="${SERVICE_CLIENT_SECRET-}"
SERVICE_SCOPE="${SERVICE_SCOPE-}"
DOCUMENT_INGEST_CLIENT_ID="${DOCUMENT_INGEST_CLIENT_ID-}"
DOCUMENT_INGEST_CLIENT_SECRET="${DOCUMENT_INGEST_CLIENT_SECRET-}"
DOCUMENT_INGEST_SCOPE="${DOCUMENT_INGEST_SCOPE-}"
DOCUMENT_REVIEW_CLIENT_ID="${DOCUMENT_REVIEW_CLIENT_ID-}"
DOCUMENT_REVIEW_CLIENT_SECRET="${DOCUMENT_REVIEW_CLIENT_SECRET-}"
DOCUMENT_REVIEW_SCOPE="${DOCUMENT_REVIEW_SCOPE-}"
AI_AGENT_CLIENT_ID="${AI_AGENT_CLIENT_ID-}"
AI_AGENT_CLIENT_SECRET="${AI_AGENT_CLIENT_SECRET-}"
AI_AGENT_SCOPE="${AI_AGENT_SCOPE-}"
BROWSER_CLIENT_ID="${BROWSER_CLIENT_ID-}"
BROWSER_CLIENT_SECRET="${BROWSER_CLIENT_SECRET-}"
MICROTX_CLIENT_ID="${MICROTX_CLIENT_ID-}"
MICROTX_CLIENT_SECRET="${MICROTX_CLIENT_SECRET-}"
MICROTX_SCOPE="${MICROTX_SCOPE-}"
MICROTX_CONSOLE_CLIENT_ID="${MICROTX_CONSOLE_CLIENT_ID-}"
MICROTX_CONSOLE_CLIENT_SECRET="${MICROTX_CONSOLE_CLIENT_SECRET-}"
MICROTX_CONSOLE_SCOPE="${MICROTX_CONSOLE_SCOPE-}"
MICROTX_CONSOLE_REDIRECT_URI="${MICROTX_CONSOLE_REDIRECT_URI-}"
MICROTX_CONSOLE_POST_LOGOUT_REDIRECT_URI="${MICROTX_CONSOLE_POST_LOGOUT_REDIRECT_URI-}"
ACCESS_TOKEN=""
JWT_PAYLOAD=""
JWKS_BODY=""
DISCOVERY_ISSUER=""
JWT_VERIFIER_DIR=""
TOKEN_VALIDATION_ERROR=""
RESPONSE_HEADERS=""

usage() {
    printf 'Usage: %s [--non-interactive]\n' "${0##*/}"
    printf 'Tests a running azn-server without changing server data.\n'
    printf '  --non-interactive  Read credentials and optional overrides from the environment.\n'
}

die() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 2
}

validate_env_file() {
    [[ -f "$ENV_FILE" ]] || return

    awk '
        /^[[:space:]]*($|#)/ { next }
        /^[A-Za-z_][A-Za-z0-9_]*=.*/ { next }
        { exit 1 }
    ' "$ENV_FILE" || die "$ENV_FILE must contain only KEY=value entries or comments"
}

env_file_count() {
    local variable_name="$1"

    awk -F= -v variable_name="$variable_name" \
        '$1 == variable_name { count++ } END { print count + 0 }' "$ENV_FILE"
}

env_file_value() {
    local variable_name="$1"

    awk -F= -v variable_name="$variable_name" \
        '$1 == variable_name { print substr($0, index($0, "=") + 1) }' "$ENV_FILE"
}

load_env_file_value() {
    local source_name="$1"
    local target_name="$2"
    local count
    local value

    [[ -n "${!target_name-}" || ! -f "$ENV_FILE" ]] && return

    count="$(env_file_count "$source_name")"
    [[ "$count" -le 1 ]] || die "$ENV_FILE must contain at most one $source_name entry"
    [[ "$count" -eq 1 ]] || return

    value="$(env_file_value "$source_name")"
    [[ "$value" != *$'\r'* ]] || die "$ENV_FILE variable $source_name contains a carriage return"
    printf -v "$target_name" '%s' "$value"
}

cleanup() {
    ADMIN_PASSWORD=""
    USER_PASSWORD=""
    SERVICE_CLIENT_SECRET=""
    DOCUMENT_INGEST_CLIENT_SECRET=""
    DOCUMENT_REVIEW_CLIENT_SECRET=""
    AI_AGENT_CLIENT_SECRET=""
    BROWSER_CLIENT_SECRET=""
    MICROTX_CLIENT_SECRET=""
    MICROTX_CONSOLE_CLIENT_SECRET=""
    ACCESS_TOKEN=""
    JWT_PAYLOAD=""
    if [[ -n "$JWT_VERIFIER_DIR" && -d "$JWT_VERIFIER_DIR" ]]; then
        rm -rf "$JWT_VERIFIER_DIR"
    fi
    unset ADMIN_PASSWORD USER_PASSWORD SERVICE_CLIENT_SECRET DOCUMENT_INGEST_CLIENT_SECRET \
        DOCUMENT_REVIEW_CLIENT_SECRET AI_AGENT_CLIENT_SECRET BROWSER_CLIENT_SECRET MICROTX_CLIENT_SECRET \
        ACCESS_TOKEN JWT_PAYLOAD
    unset MICROTX_CONSOLE_CLIENT_SECRET
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    printf '  ✓ %s\n' "$1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf '  ✗ %s\n' "$1" >&2
}

skip() {
    printf '  - %s\n' "$1"
}

body_contains() {
    local pattern="$1"
    printf '%s' "$RESPONSE_BODY" | grep -Eq -- "$pattern"
}

print_curl_command() {
    local basic_identity="${1-}"
    shift

    # %q makes the displayed request safe to copy into Bash while preserving
    # the actual request arguments. Credentials never reach this function.
    printf '    CURL:'
    printf ' %q' curl --silent --show-error --connect-timeout 5 --max-time 15
    if [[ -n "$basic_identity" ]]; then
        printf ' %q %q' --user "${basic_identity}:<redacted>"
    fi
    printf ' %q' "$@"
    printf '\n'
}

perform_request() {
    local output

    RESPONSE_BODY=""
    RESPONSE_STATUS=""
    print_curl_command "" "$@"
    if ! output="$(curl --silent --show-error \
            --connect-timeout 5 \
            --max-time 15 \
            --write-out $'\n%{http_code}' \
            "$@")"; then
        return 1
    fi

    RESPONSE_STATUS="${output##*$'\n'}"
    RESPONSE_BODY="${output%$'\n'*}"
}

perform_headers_only_request() {
    local output

    RESPONSE_BODY=""
    RESPONSE_HEADERS=""
    RESPONSE_STATUS=""
    print_curl_command "" "$@"
    if ! output="$(curl --silent --show-error \
            --connect-timeout 5 \
            --max-time 15 \
            --dump-header - \
            --output /dev/null \
            --write-out $'\n%{http_code}' \
            "$@")"; then
        return 1
    fi

    RESPONSE_STATUS="${output##*$'\n'}"
    RESPONSE_HEADERS="${output%$'\n'*}"
}

curl_config_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

perform_basic_request() {
    local username="$1"
    local password="$2"
    local escaped_username
    local escaped_password
    local output
    shift 2

    escaped_username="$(curl_config_escape "$username")"
    escaped_password="$(curl_config_escape "$password")"
    RESPONSE_BODY=""
    RESPONSE_STATUS=""
    print_curl_command "$username" "$@"

    if ! output="$(
        printf 'user = "%s:%s"\n' "$escaped_username" "$escaped_password" |
            curl --silent --show-error \
                --connect-timeout 5 \
                --max-time 15 \
                --config - \
                --write-out $'\n%{http_code}' \
                "$@"
    )"; then
        return 1
    fi

    RESPONSE_STATUS="${output##*$'\n'}"
    RESPONSE_BODY="${output%$'\n'*}"
}

decode_jwt_payload() {
    decode_base64url "$1"
}

decode_base64url() {
    local encoded_value="$1"
    local remainder

    encoded_value="${encoded_value//-/+}"
    encoded_value="${encoded_value//_/\/}"
    remainder=$(( ${#encoded_value} % 4 ))
    if [[ "$remainder" -eq 2 ]]; then
        encoded_value="${encoded_value}=="
    elif [[ "$remainder" -eq 3 ]]; then
        encoded_value="${encoded_value}="
    elif [[ "$remainder" -eq 1 ]]; then
        return 1
    fi

    printf '%s' "$encoded_value" | openssl base64 -d -A 2>/dev/null
}

json_string_value() {
    local json="$1"
    local name="$2"

    printf '%s' "$json" |
        sed -n "s/.*\"$name\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p"
}

json_first_array_value() {
    local json="$1"
    local name="$2"

    printf '%s' "$json" |
        sed -n "s/.*\"$name\"[[:space:]]*:[[:space:]]*\[[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p"
}

json_array_values() {
    local json="$1"
    local name="$2"
    local values

    values="$(printf '%s' "$json" |
        sed -n "s/.*\"$name\"[[:space:]]*:[[:space:]]*\[\\([^]]*\\)\].*/\\1/p" |
        tr -d '"[:space:]')"
    printf '%s' "${values:-none}"
}

json_boolean_value() {
    local json="$1"
    local name="$2"

    if printf '%s' "$json" | grep -Eq "\"$name\"[[:space:]]*:[[:space:]]*true"; then
        printf 'true'
    elif printf '%s' "$json" | grep -Eq "\"$name\"[[:space:]]*:[[:space:]]*false"; then
        printf 'false'
    fi
}

format_epoch() {
    local epoch="$1"

    [[ "$epoch" =~ ^[0-9]+$ ]] || {
        printf 'not-present'
        return
    }

    if date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
        date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ'
    elif date -u -d "@$epoch" '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
        date -u -d "@$epoch" '+%Y-%m-%dT%H:%M:%SZ'
    else
        printf '%s (epoch seconds)' "$epoch"
    fi
}

section() {
    printf '\n━━━ %s ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n' "$1"
}

print_authorization_server_discovery() {
    local issuer
    local authorization_endpoint
    local token_endpoint
    local jwks_uri
    local introspection_endpoint
    local revocation_endpoint
    local grant_types
    local client_authentication
    local dpop_algorithms
    local mtls_bound_tokens

    issuer="$(json_string_value "$RESPONSE_BODY" issuer)"
    authorization_endpoint="$(json_string_value "$RESPONSE_BODY" authorization_endpoint)"
    token_endpoint="$(json_string_value "$RESPONSE_BODY" token_endpoint)"
    jwks_uri="$(json_string_value "$RESPONSE_BODY" jwks_uri)"
    introspection_endpoint="$(json_string_value "$RESPONSE_BODY" introspection_endpoint)"
    revocation_endpoint="$(json_string_value "$RESPONSE_BODY" revocation_endpoint)"
    grant_types="$(json_array_values "$RESPONSE_BODY" grant_types_supported)"
    client_authentication="$(json_array_values "$RESPONSE_BODY" token_endpoint_auth_methods_supported)"
    dpop_algorithms="$(json_array_values "$RESPONSE_BODY" dpop_signing_alg_values_supported)"
    mtls_bound_tokens="$(json_boolean_value "$RESPONSE_BODY" tls_client_certificate_bound_access_tokens)"

    printf '%s\n' \
        '    OAuth authorization-server configuration:' \
        "      issuer: ${issuer:-not-advertised}" \
        "      authorization endpoint: ${authorization_endpoint:-not-advertised}" \
        "      token endpoint: ${token_endpoint:-not-advertised}" \
        "      JWKS URI: ${jwks_uri:-not-advertised}" \
        "      introspection endpoint: ${introspection_endpoint:-not-advertised}" \
        "      revocation endpoint: ${revocation_endpoint:-not-advertised}" \
        "      grant types: $grant_types" \
        "      token client authentication: $client_authentication" \
        "      DPoP signing algorithms: $dpop_algorithms"
    printf '      PKCE S256: %s; mTLS-bound access tokens: %s\n' \
        "$(body_contains '"code_challenge_methods_supported"[^]]*"S256"' && printf yes || printf no)" \
        "${mtls_bound_tokens:-not-advertised}"
}

print_oidc_discovery() {
    local issuer
    local userinfo_endpoint
    local end_session_endpoint
    local scopes
    local subject_types
    local id_token_algorithms

    issuer="$(json_string_value "$RESPONSE_BODY" issuer)"
    userinfo_endpoint="$(json_string_value "$RESPONSE_BODY" userinfo_endpoint)"
    end_session_endpoint="$(json_string_value "$RESPONSE_BODY" end_session_endpoint)"
    scopes="$(json_array_values "$RESPONSE_BODY" scopes_supported)"
    subject_types="$(json_array_values "$RESPONSE_BODY" subject_types_supported)"
    id_token_algorithms="$(json_array_values "$RESPONSE_BODY" id_token_signing_alg_values_supported)"
    DISCOVERY_ISSUER="$issuer"

    printf '%s\n' \
        '    OpenID Connect configuration:' \
        "      userinfo endpoint: ${userinfo_endpoint:-not-advertised}" \
        "      logout/end-session endpoint: ${end_session_endpoint:-not-advertised}" \
        "      scopes: $scopes; subject types: $subject_types" \
        "      ID-token signing algorithms: $id_token_algorithms"
}

create_jwt_verifier() {
    local verifier_source

    [[ -n "$JWT_VERIFIER_DIR" ]] && return
    JWT_VERIFIER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cloudbank-jwt.XXXXXX")" || return 1
    chmod 700 "$JWT_VERIFIER_DIR" || return 1
    verifier_source="$JWT_VERIFIER_DIR/JwtVerifier.java"
    cat > "$verifier_source" <<'EOF'
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.PublicKey;
import java.security.Signature;
import java.security.spec.RSAPublicKeySpec;
import java.util.Base64;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

class JwtVerifier {
    private static final Base64.Decoder URL = Base64.getUrlDecoder();

    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
        String token = input.readLine();
        String jwksEncoded = input.readLine();
        if (token == null || jwksEncoded == null) throw new IllegalArgumentException("missing verifier input");
        String[] parts = token.split("\\.", -1);
        if (parts.length != 3) throw new IllegalArgumentException("invalid JWT");
        String header = new String(URL.decode(parts[0]), StandardCharsets.UTF_8);
        String algorithm = stringValue(header, "alg");
        String keyId = stringValue(header, "kid");
        if (!"RS256".equals(algorithm) || keyId == null || keyId.isBlank()) {
            throw new IllegalArgumentException("unsupported JWT signing header");
        }
        String jwks = new String(URL.decode(jwksEncoded), StandardCharsets.UTF_8);
        String key = keyForId(jwks, keyId);
        String modulus = stringValue(key, "n");
        String exponent = stringValue(key, "e");
        if (modulus == null || exponent == null) throw new IllegalArgumentException("RSA JWK is incomplete");
        PublicKey publicKey = KeyFactory.getInstance("RSA").generatePublic(new RSAPublicKeySpec(
                new BigInteger(1, URL.decode(modulus)), new BigInteger(1, URL.decode(exponent))));
        Signature verifier = Signature.getInstance("SHA256withRSA");
        verifier.initVerify(publicKey);
        verifier.update((parts[0] + "." + parts[1]).getBytes(StandardCharsets.US_ASCII));
        if (!verifier.verify(URL.decode(parts[2]))) throw new IllegalArgumentException("JWT signature is invalid");
    }

    private static String stringValue(String json, String name) {
        Matcher matcher = Pattern.compile("\\\"" + Pattern.quote(name)
                + "\\\"\\s*:\\s*\\\"([^\\\"]*)\\\"").matcher(json);
        return matcher.find() ? matcher.group(1) : null;
    }

    private static String keyForId(String jwks, String keyId) {
        Matcher matcher = Pattern.compile("\\{[^{}]*\\}").matcher(jwks);
        while (matcher.find()) {
            String key = matcher.group();
            if (keyId.equals(stringValue(key, "kid"))) return key;
        }
        throw new IllegalArgumentException("JWT key id is not published");
    }
}
EOF
    chmod 600 "$verifier_source"
}

verify_jwt_signature() {
    local token="$1"

    create_jwt_verifier || return 1
    printf '%s\n%s\n' "$token" "$(printf '%s' "$JWKS_BODY" | openssl base64 -A | tr '+/' '-_' | tr -d '=')" |
        java "$JWT_VERIFIER_DIR/JwtVerifier.java" >/dev/null 2>&1
}

claim_contains() {
    local payload="$1"
    local name="$2"
    local expected="$3"
    local value

    value="$(json_string_value "$payload" "$name")"
    [[ "$value" == "$expected" ]] && return 0
    value="$(json_array_values "$payload" "$name")"
    [[ ",$value," == *",$expected,"* ]]
}

validate_token_contract() {
    local token="$1"
    local expected_client_id="$2"
    local expected_scope="$3"
    local expected_audience="$4"
    local expected_roles="$5"
    local header
    local algorithm
    local key_id
    local expires_at
    local issued_at

    TOKEN_VALIDATION_ERROR=""
    [[ "$token" == *.*.* ]] || { TOKEN_VALIDATION_ERROR="access token was not a JWT"; return 1; }
    header="$(decode_base64url "$(printf '%s' "$token" | cut -d. -f1)")" || {
        TOKEN_VALIDATION_ERROR="JWT header could not be decoded"; return 1;
    }
    JWT_PAYLOAD="$(decode_jwt_payload "$(printf '%s' "$token" | cut -d. -f2)")" || {
        TOKEN_VALIDATION_ERROR="JWT payload could not be decoded"; return 1;
    }
    algorithm="$(json_string_value "$header" alg)"
    key_id="$(json_string_value "$header" kid)"
    [[ "$algorithm" == "RS256" && -n "$key_id" ]] || {
        TOKEN_VALIDATION_ERROR="expected an RS256 JWT with a key id"; return 1;
    }
    verify_jwt_signature "$token" || {
        TOKEN_VALIDATION_ERROR="JWT signature did not verify against the published JWKS"; return 1;
    }
    [[ "$(json_string_value "$JWT_PAYLOAD" iss)" == "$DISCOVERY_ISSUER" ]] || {
        TOKEN_VALIDATION_ERROR="issuer did not match OIDC discovery"; return 1;
    }
    claim_contains "$JWT_PAYLOAD" aud "$expected_audience" || {
        TOKEN_VALIDATION_ERROR="expected audience was missing"; return 1;
    }
    claim_contains "$JWT_PAYLOAD" scope "$expected_scope" || {
        TOKEN_VALIDATION_ERROR="expected scope was missing"; return 1;
    }
    [[ "$(json_string_value "$JWT_PAYLOAD" client_id)" == "$expected_client_id" ]] || {
        TOKEN_VALIDATION_ERROR="client identity was missing"; return 1;
    }
    [[ "$(json_string_value "$JWT_PAYLOAD" token_kind)" == "service" ]] || {
        TOKEN_VALIDATION_ERROR="token kind was not service"; return 1;
    }
    if [[ "$expected_roles" == "none" ]]; then
        printf '%s' "$JWT_PAYLOAD" | grep -Eq '"roles"[[:space:]]*:[[:space:]]*\[[[:space:]]*\]' || {
            TOKEN_VALIDATION_ERROR="service token roles were not empty"; return 1;
        }
    else
        local role
        IFS=',' read -r -a roles <<< "$expected_roles"
        for role in "${roles[@]}"; do
            claim_contains "$JWT_PAYLOAD" roles "$role" || {
                TOKEN_VALIDATION_ERROR="required role was missing"; return 1;
            }
        done
    fi
    expires_at="$(printf '%s' "$JWT_PAYLOAD" | sed -n 's/.*"exp"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"
    issued_at="$(printf '%s' "$JWT_PAYLOAD" | sed -n 's/.*"iat"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"
    [[ "$expires_at" =~ ^[0-9]+$ && "$issued_at" =~ ^[0-9]+$ && "$expires_at" -gt "$issued_at" ]] || {
        TOKEN_VALIDATION_ERROR="issued-at or expiry claim was invalid"; return 1;
    }
}

check_machine_client() {
    local label="$1"
    local client_id="$2"
    local client_secret="$3"
    local scope="$4"
    local expected_audience="$5"
    local expected_roles="$6"

    printf '\n  %s\n' "$label"
    if ! perform_basic_request "$client_id" "$client_secret" \
            --request POST --header "Content-Type: application/x-www-form-urlencoded" \
            --data-urlencode "grant_type=client_credentials" --data-urlencode "scope=$scope" \
            "$BASE_URL/oauth2/token"; then
        fail "$label token issuance (request failed)"
    elif [[ "$RESPONSE_STATUS" != "200" ]] || ! body_contains '"access_token"[[:space:]]*:' ||
            ! body_contains '"token_type"[[:space:]]*:[[:space:]]*"Bearer"'; then
        fail "$label token issuance (expected HTTP 200 bearer response, received $RESPONSE_STATUS)"
    else
        ACCESS_TOKEN="$(printf '%s' "$RESPONSE_BODY" |
            sed -n 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
        if ! validate_token_contract "$ACCESS_TOKEN" "$client_id" "$scope" "$expected_audience" "$expected_roles"; then
            fail "$label token contract ($TOKEN_VALIDATION_ERROR)"
        else
            pass "Token issued; signature and contract verified"
            print_jwt_summary "$label" "$ACCESS_TOKEN" "$JWT_PAYLOAD" ||
                fail "$label token claim summary could not be decoded"
        fi
    fi
    ACCESS_TOKEN=""
    JWT_PAYLOAD=""
}

check_invalid_machine_client_secret() {
    local label="$1"
    local client_id="$2"
    local client_secret="$3"
    local scope="$4"

    if ! perform_basic_request "$client_id" "${client_secret}invalid" \
            --request POST --header "Content-Type: application/x-www-form-urlencoded" \
            --data-urlencode "grant_type=client_credentials" --data-urlencode "scope=$scope" \
            "$BASE_URL/oauth2/token"; then
        fail "$label invalid secret rejection (request failed)"
    elif [[ "$RESPONSE_STATUS" != "401" ]]; then
        fail "$label invalid secret rejection (expected HTTP 401, received $RESPONSE_STATUS)"
    else
        pass "$label invalid secret is rejected"
    fi
}

check_unauthorized_scope() {
    local label="$1"
    local client_id="$2"
    local client_secret="$3"
    local scope="$4"

    if ! perform_basic_request "$client_id" "$client_secret" \
            --request POST --header "Content-Type: application/x-www-form-urlencoded" \
            --data-urlencode "grant_type=client_credentials" --data-urlencode "scope=$scope" \
            "$BASE_URL/oauth2/token"; then
        fail "$label unauthorized-scope rejection (request failed)"
    elif [[ "$RESPONSE_STATUS" != "400" ]] || ! body_contains '"error"[[:space:]]*:[[:space:]]*"invalid_scope"'; then
        fail "$label unauthorized-scope rejection (expected HTTP 400 invalid_scope)"
    else
        pass "$label unauthorized scope is rejected"
    fi
}

check_authorization_code_client() {
    local label="$1"
    local client_id="$2"
    local scope="$3"
    local redirect_uri="$4"
    local requested_scope="${scope//,/ }"

    if ! perform_headers_only_request --get \
            --data-urlencode "response_type=code" \
            --data-urlencode "client_id=$client_id" \
            --data-urlencode "scope=$requested_scope" \
            --data-urlencode "redirect_uri=$redirect_uri" \
            --data-urlencode "state=cloudbank-azn-smoke-test" \
            --data-urlencode "code_challenge=dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk" \
            --data-urlencode "code_challenge_method=S256" \
            "$BASE_URL/oauth2/authorize"; then
        fail "$label authorization request (request failed)"
    elif [[ "$RESPONSE_STATUS" != "302" ]]; then
        fail "$label authorization request (expected HTTP 302 login redirect, received $RESPONSE_STATUS)"
    else
        pass "$label accepts an authorization-code + PKCE request"
    fi
}

print_jwt_summary() {
    local label="$1"
    local token="$2"
    local payload="$3"
    local header
    local algorithm
    local key_id
    local issuer
    local audience
    local scope
    local roles
    local client_id
    local token_kind
    local expires_at

    header="$(decode_base64url "$(printf '%s' "$token" | cut -d. -f1)")" || return 1
    algorithm="$(json_string_value "$header" alg)"
    key_id="$(json_string_value "$header" kid)"
    issuer="$(json_string_value "$payload" iss)"
    audience="$(json_string_value "$payload" aud)"
    [[ -n "$audience" ]] || audience="$(json_first_array_value "$payload" aud)"
    scope="$(json_array_values "$payload" scope)"
    roles="$(json_array_values "$payload" roles)"
    client_id="$(json_string_value "$payload" client_id)"
    token_kind="$(json_string_value "$payload" token_kind)"
    expires_at="$(json_string_value "$payload" exp)"
    [[ -n "$expires_at" ]] || expires_at="$(printf '%s' "$payload" | sed -n 's/.*"exp"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"

    printf '%s\n' \
        '    Token details (raw token redacted):' \
        "      signing: ${algorithm:-not-present}; key ID: ${key_id:-not-present}" \
        "      issuer: ${issuer:-not-present}; audience: ${audience:-not-present}" \
        "      client ID: ${client_id:-not-present}; scope: $scope; roles: $roles" \
        "      token kind: ${token_kind:-not-present}; expires: $(format_epoch "$expires_at")"
}

check_endpoint() {
    local name="$1"
    local endpoint="$2"
    local expected_status="$3"
    shift 3

    if ! perform_request "$BASE_URL$endpoint"; then
        fail "$name (request failed)"
        return 1
    fi
    if [[ "$RESPONSE_STATUS" != "$expected_status" ]]; then
        fail "$name (expected HTTP $expected_status, received $RESPONSE_STATUS)"
        return 1
    fi

    local pattern
    for pattern in "$@"; do
        if ! body_contains "$pattern"; then
            fail "$name (response did not contain expected content)"
            return 1
        fi
    done
    pass "$name"
}

check_basic_endpoint() {
    local name="$1"
    local endpoint="$2"
    local username="$3"
    local password="$4"
    shift 4

    if ! perform_basic_request "$username" "$password" "$BASE_URL$endpoint"; then
        fail "$name (request failed)"
        return
    fi
    if [[ "$RESPONSE_STATUS" != "200" ]]; then
        fail "$name (expected HTTP 200, received $RESPONSE_STATUS)"
        return
    fi

    local pattern
    for pattern in "$@"; do
        if ! body_contains "$pattern"; then
            fail "$name (response did not contain expected content)"
            return
        fi
    done
    pass "$name"
}

check_basic_endpoint_status() {
    local name="$1"
    local endpoint="$2"
    local username="$3"
    local password="$4"
    local expected_status="$5"
    shift 5

    if ! perform_basic_request "$username" "$password" "$BASE_URL$endpoint"; then
        fail "$name (request failed)"
        return
    fi
    if [[ "$RESPONSE_STATUS" != "$expected_status" ]]; then
        fail "$name (expected HTTP $expected_status, received $RESPONSE_STATUS)"
        return
    fi

    local pattern
    for pattern in "$@"; do
        if ! body_contains "$pattern"; then
            fail "$name (response did not contain expected content)"
            return
        fi
    done
    pass "$name"
}

check_basic_endpoint_without_secret_fields() {
    local name="$1"
    local endpoint="$2"
    local username="$3"
    local password="$4"
    shift 4

    if ! perform_basic_request "$username" "$password" "$BASE_URL$endpoint"; then
        fail "$name (request failed)"
        return
    fi
    if [[ "$RESPONSE_STATUS" != "200" ]]; then
        fail "$name (expected HTTP 200, received $RESPONSE_STATUS)"
        return
    fi

    local pattern
    for pattern in "$@"; do
        if ! body_contains "$pattern"; then
            fail "$name (response did not contain expected content)"
            return
        fi
    done
    if body_contains '"password"[[:space:]]*:' || body_contains '"otp"[[:space:]]*:'; then
        fail "$name (response contained a secret field)"
        return
    fi
    pass "$name"
}

prompt_with_default() {
    local variable_name="$1"
    local label="$2"
    local default_value="$3"
    local entered_value

    IFS= read -r -p "$label [$default_value]: " entered_value
    if [[ -z "$entered_value" ]]; then
        entered_value="$default_value"
    fi
    printf -v "$variable_name" '%s' "$entered_value"
}

prompt_secret() {
    local variable_name="$1"
    local label="$2"
    local entered_value

    IFS= read -r -s -p "$label: " entered_value
    printf '\n'
    if [[ -z "$entered_value" ]]; then
        die "$label must not be empty"
    fi
    printf -v "$variable_name" '%s' "$entered_value"
}

case "${1-}" in
    -h | --help) usage; exit 0 ;;
    --non-interactive) NON_INTERACTIVE=true ;;
    "") ;;
    *) usage >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { usage >&2; exit 2; }

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v grep >/dev/null 2>&1 || die "grep is required"
command -v openssl >/dev/null 2>&1 || die "openssl is required"
command -v java >/dev/null 2>&1 || die "java is required to verify JWT signatures"
command -v mktemp >/dev/null 2>&1 || die "mktemp is required to verify JWT signatures"
validate_env_file
load_env_file_value AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD ADMIN_PASSWORD
load_env_file_value AZN_BOOTSTRAP_USERS_USER_PASSWORD USER_PASSWORD
load_env_file_value AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET SERVICE_CLIENT_SECRET
load_env_file_value AZN_AUTHORIZATION_SERVER_DOCUMENT_INGEST_CLIENT_SECRET DOCUMENT_INGEST_CLIENT_SECRET
load_env_file_value AZN_AUTHORIZATION_SERVER_DOCUMENT_REVIEW_CLIENT_SECRET DOCUMENT_REVIEW_CLIENT_SECRET
load_env_file_value AZN_AUTHORIZATION_SERVER_AI_AGENT_CLIENT_SECRET AI_AGENT_CLIENT_SECRET
load_env_file_value AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET BROWSER_CLIENT_SECRET
load_env_file_value AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET MICROTX_CLIENT_SECRET
load_env_file_value AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_ID MICROTX_CONSOLE_CLIENT_ID
load_env_file_value AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_SECRET MICROTX_CONSOLE_CLIENT_SECRET
load_env_file_value AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_SCOPES MICROTX_CONSOLE_SCOPE
load_env_file_value AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_REDIRECT_URI MICROTX_CONSOLE_REDIRECT_URI
load_env_file_value AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_POST_LOGOUT_REDIRECT_URI \
    MICROTX_CONSOLE_POST_LOGOUT_REDIRECT_URI
if [[ "$NON_INTERACTIVE" == "true" ]]; then
    BASE_URL="${BASE_URL:-$DEFAULT_BASE_URL}"
    ADMIN_USERNAME="${ADMIN_USERNAME:-$DEFAULT_ADMIN_USERNAME}"
    SERVICE_CLIENT_ID="${SERVICE_CLIENT_ID:-$DEFAULT_SERVICE_CLIENT_ID}"
    SERVICE_SCOPE="${SERVICE_SCOPE:-$DEFAULT_SERVICE_SCOPE}"
    DOCUMENT_INGEST_CLIENT_ID="${DOCUMENT_INGEST_CLIENT_ID:-$DEFAULT_DOCUMENT_INGEST_CLIENT_ID}"
    DOCUMENT_INGEST_SCOPE="${DOCUMENT_INGEST_SCOPE:-$DEFAULT_DOCUMENT_SERVICE_SCOPE}"
    DOCUMENT_REVIEW_CLIENT_ID="${DOCUMENT_REVIEW_CLIENT_ID:-$DEFAULT_DOCUMENT_REVIEW_CLIENT_ID}"
    DOCUMENT_REVIEW_SCOPE="${DOCUMENT_REVIEW_SCOPE:-$DEFAULT_DOCUMENT_SERVICE_SCOPE}"
    AI_AGENT_CLIENT_ID="${AI_AGENT_CLIENT_ID:-$DEFAULT_AI_AGENT_CLIENT_ID}"
    AI_AGENT_SCOPE="${AI_AGENT_SCOPE:-$DEFAULT_DOCUMENT_SERVICE_SCOPE}"
    BROWSER_CLIENT_ID="${BROWSER_CLIENT_ID:-$DEFAULT_BROWSER_CLIENT_ID}"
    MICROTX_CLIENT_ID="${MICROTX_CLIENT_ID:-$DEFAULT_MICROTX_CLIENT_ID}"
    MICROTX_SCOPE="${MICROTX_SCOPE:-$DEFAULT_MICROTX_SCOPE}"
    MICROTX_CONSOLE_CLIENT_ID="${MICROTX_CONSOLE_CLIENT_ID:-$DEFAULT_MICROTX_CONSOLE_CLIENT_ID}"
    MICROTX_CONSOLE_SCOPE="${MICROTX_CONSOLE_SCOPE:-$DEFAULT_MICROTX_CONSOLE_SCOPE}"
    [[ -n "$ADMIN_PASSWORD" ]] || die "ADMIN_PASSWORD is required in non-interactive mode"
    [[ -n "$SERVICE_CLIENT_SECRET" ]] || die "SERVICE_CLIENT_SECRET is required in non-interactive mode"
    [[ -n "$DOCUMENT_INGEST_CLIENT_SECRET" ]] || die "DOCUMENT_INGEST_CLIENT_SECRET is required in non-interactive mode"
    [[ -n "$DOCUMENT_REVIEW_CLIENT_SECRET" ]] || die "DOCUMENT_REVIEW_CLIENT_SECRET is required in non-interactive mode"
    [[ -n "$AI_AGENT_CLIENT_SECRET" ]] || die "AI_AGENT_CLIENT_SECRET is required in non-interactive mode"
    [[ -n "$BROWSER_CLIENT_SECRET" ]] || die "BROWSER_CLIENT_SECRET is required in non-interactive mode"
    [[ -n "$MICROTX_CLIENT_SECRET" ]] || die "MICROTX_CLIENT_SECRET is required in non-interactive mode"
else
    [[ -t 0 ]] || die "interactive input is required for credential prompts"
    prompt_with_default BASE_URL "azn-server base URL" "$DEFAULT_BASE_URL"

    printf 'Administrative Basic authentication\n'
    prompt_with_default ADMIN_USERNAME "Admin username" "$DEFAULT_ADMIN_USERNAME"
    prompt_secret ADMIN_PASSWORD "Admin password"

    printf '\nService OAuth client credentials\n'
    prompt_with_default SERVICE_CLIENT_ID "Service OAuth client ID" "$DEFAULT_SERVICE_CLIENT_ID"
    prompt_secret SERVICE_CLIENT_SECRET "Service OAuth client secret"
    prompt_with_default SERVICE_SCOPE "Service OAuth scope" "$DEFAULT_SERVICE_SCOPE"

    printf '\nDocument-ingest OAuth client credentials\n'
    prompt_with_default DOCUMENT_INGEST_CLIENT_ID "Document-ingest OAuth client ID" "$DEFAULT_DOCUMENT_INGEST_CLIENT_ID"
    prompt_secret DOCUMENT_INGEST_CLIENT_SECRET "Document-ingest OAuth client secret"
    prompt_with_default DOCUMENT_INGEST_SCOPE "Document-ingest OAuth scope" "$DEFAULT_DOCUMENT_SERVICE_SCOPE"

    printf '\nDocument-review OAuth client credentials\n'
    prompt_with_default DOCUMENT_REVIEW_CLIENT_ID "Document-review OAuth client ID" "$DEFAULT_DOCUMENT_REVIEW_CLIENT_ID"
    prompt_secret DOCUMENT_REVIEW_CLIENT_SECRET "Document-review OAuth client secret"
    prompt_with_default DOCUMENT_REVIEW_SCOPE "Document-review OAuth scope" "$DEFAULT_DOCUMENT_SERVICE_SCOPE"

    printf '\nAI-agent OAuth client credentials\n'
    prompt_with_default AI_AGENT_CLIENT_ID "AI-agent OAuth client ID" "$DEFAULT_AI_AGENT_CLIENT_ID"
    prompt_secret AI_AGENT_CLIENT_SECRET "AI-agent OAuth client secret"
    prompt_with_default AI_AGENT_SCOPE "AI-agent OAuth scope" "$DEFAULT_DOCUMENT_SERVICE_SCOPE"

    printf '\nBrowser/BFF OAuth client credentials\n'
    prompt_with_default BROWSER_CLIENT_ID "Browser OAuth client ID" "$DEFAULT_BROWSER_CLIENT_ID"
    prompt_secret BROWSER_CLIENT_SECRET "Browser OAuth client secret"

    printf '\nMicroTx Workflow OAuth client credentials\n'
    prompt_with_default MICROTX_CLIENT_ID "MicroTx OAuth client ID" "$DEFAULT_MICROTX_CLIENT_ID"
    prompt_secret MICROTX_CLIENT_SECRET "MicroTx OAuth client secret"
    prompt_with_default MICROTX_SCOPE "MicroTx OAuth scope" "$DEFAULT_MICROTX_SCOPE"
fi

if [[ -n "$MICROTX_CONSOLE_CLIENT_SECRET$MICROTX_CONSOLE_REDIRECT_URI$MICROTX_CONSOLE_POST_LOGOUT_REDIRECT_URI" ]]; then
    [[ -n "$MICROTX_CONSOLE_CLIENT_SECRET" ]] ||
        die "MICROTX_CONSOLE_CLIENT_SECRET is required when MicroTx Console is configured"
    [[ -n "$MICROTX_CONSOLE_REDIRECT_URI" ]] ||
        die "MICROTX_CONSOLE_REDIRECT_URI is required when MicroTx Console is configured"
fi

if [[ -n "$USER_PASSWORD" ]]; then
    USER_USERNAME="${USER_USERNAME:-$DEFAULT_USER_USERNAME}"
fi

BASE_URL="${BASE_URL%/}"
case "$BASE_URL" in
    http://* | https://*) ;;
    *) die "base URL must start with http:// or https://" ;;
esac

printf '%s\n' \
    'CloudBank Authorization Server smoke test' \
    "Target: $BASE_URL" \
    'Mode: read-only; downstream services are not started'
printf '\nConfiguration in use\n'
printf '%s\n' \
    "  Bootstrap-user role boundaries: $([[ -n "$USER_PASSWORD" ]] && printf enabled || printf password-not-available)" \
    "  Browser/BFF client: $BROWSER_CLIENT_ID (authorization code + PKCE)" \
    "  Shared service client: $SERVICE_CLIENT_ID (scope: $SERVICE_SCOPE)" \
    "  Document ingest client: $DOCUMENT_INGEST_CLIENT_ID (scope: $DOCUMENT_INGEST_SCOPE)" \
    "  Document review client: $DOCUMENT_REVIEW_CLIENT_ID (scope: $DOCUMENT_REVIEW_SCOPE)" \
    "  AI agent client: $AI_AGENT_CLIENT_ID (scope: $AI_AGENT_SCOPE)" \
    "  MicroTx client: $MICROTX_CLIENT_ID (scope: $MICROTX_SCOPE)"
if [[ -n "$MICROTX_CONSOLE_CLIENT_SECRET" ]]; then
    printf '  MicroTx Console client: %s (authorization code + PKCE)\n' "$MICROTX_CONSOLE_CLIENT_ID"
else
    printf '%s\n' '  MicroTx Console client: not configured (optional)'
fi

section "1. Platform and OIDC"
check_endpoint "Actuator health" "/actuator/health" "200" \
    '"status"[[:space:]]*:[[:space:]]*"UP"'
check_endpoint "Actuator info" "/actuator/info" "200"
check_endpoint "Actuator root rejects anonymous access" "/actuator" "401"
if check_endpoint "OAuth authorization-server metadata" \
    "/.well-known/oauth-authorization-server" "200" \
    '"issuer"' '"authorization_endpoint"' '"token_endpoint"' '"jwks_uri"'; then
    print_authorization_server_discovery
fi
if check_endpoint "OpenID Connect metadata" \
    "/.well-known/openid-configuration" "200" \
    '"issuer"' '"authorization_endpoint"' '"token_endpoint"' '"userinfo_endpoint"' '"jwks_uri"'; then
    print_oidc_discovery
fi
check_endpoint "JWKS signing key" "/oauth2/jwks" "200" \
    '"keys"[[:space:]]*:' '"kty"[[:space:]]*:[[:space:]]*"RSA"' '"kid"[[:space:]]*:'
JWKS_BODY="$RESPONSE_BODY"
check_endpoint "Anonymous ping" "/user/api/v1/ping" "200" "Ping Pong"
check_endpoint "Protected endpoint rejects anonymous access" \
    "/user/api/v1/connect" "401"

section "2. Internal access controls"
check_basic_endpoint "Authenticated admin connection" "/user/api/v1/connect" \
    "$ADMIN_USERNAME" "$ADMIN_PASSWORD" "ROLE_USER" "ROLE_ADMIN" "ROLE_CONFIG_EDITOR"
if [[ "$ADMIN_USERNAME" == "$DEFAULT_ADMIN_USERNAME" ]]; then
    check_basic_endpoint "Demo admin HUMAN-review grant" "/user/api/v1/connect" \
        "$ADMIN_USERNAME" "$ADMIN_PASSWORD" "ROLE_UNDERWRITER"
fi
check_basic_endpoint "Admin user authorization" "/user/api/v1/pinguser" \
    "$ADMIN_USERNAME" "$ADMIN_PASSWORD" "Secure User Ping Pong"
check_basic_endpoint "Admin role authorization" "/user/api/v1/pingadmin" \
    "$ADMIN_USERNAME" "$ADMIN_PASSWORD" "Secure Admin Ping Pong"
check_basic_endpoint "Admin configuration-editor authorization" "/user/api/v1/pingceditor" \
    "$ADMIN_USERNAME" "$ADMIN_PASSWORD" "Secure Content Editor Soccer"
check_basic_endpoint_without_secret_fields "Admin user lookup avoids secrets" \
    "/user/api/v1/findUser?username=$ADMIN_USERNAME" "$ADMIN_USERNAME" "$ADMIN_PASSWORD" \
    "\"username\"[[:space:]]*:[[:space:]]*\"$ADMIN_USERNAME\"" '"roles"'

if [[ -n "$USER_PASSWORD" ]]; then
    check_basic_endpoint "Bootstrap user connection" "/user/api/v1/connect" \
        "$USER_USERNAME" "$USER_PASSWORD" "ROLE_USER"
    check_basic_endpoint "Bootstrap user authorization" "/user/api/v1/pinguser" \
        "$USER_USERNAME" "$USER_PASSWORD" "Secure User Ping Pong"
    check_basic_endpoint_status "Bootstrap user cannot administer" "/user/api/v1/pingadmin" \
        "$USER_USERNAME" "$USER_PASSWORD" "403"
    check_basic_endpoint_status "Bootstrap user cannot edit configuration" "/user/api/v1/pingceditor" \
        "$USER_USERNAME" "$USER_PASSWORD" "403"
else
    skip "Bootstrap-user role boundaries (set USER_PASSWORD to enable)"
fi

section "3. Service-token contracts"
check_machine_client "Loan application workflow-task service token" \
    "$SERVICE_CLIENT_ID" "$SERVICE_CLIENT_SECRET" "$SERVICE_SCOPE" "cloudbank-api" "none"
check_machine_client "Document ingest service token" "$DOCUMENT_INGEST_CLIENT_ID" "$DOCUMENT_INGEST_CLIENT_SECRET" \
    "$DOCUMENT_INGEST_SCOPE" "cloudbank-api" "none"
check_machine_client "Document review service token" "$DOCUMENT_REVIEW_CLIENT_ID" "$DOCUMENT_REVIEW_CLIENT_SECRET" \
    "$DOCUMENT_REVIEW_SCOPE" "cloudbank-api" "none"
check_machine_client "AI agent service token" "$AI_AGENT_CLIENT_ID" "$AI_AGENT_CLIENT_SECRET" \
    "$AI_AGENT_SCOPE" "cloudbank-api" "none"
check_machine_client "Geographic risk internal API service token" \
    "$SERVICE_CLIENT_ID" "$SERVICE_CLIENT_SECRET" "$SERVICE_SCOPE" "cloudbank-api" "none"
check_machine_client "Policy retrieval resource-server service token" \
    "$SERVICE_CLIENT_ID" "$SERVICE_CLIENT_SECRET" "$SERVICE_SCOPE" "cloudbank-api" "none"
check_machine_client "Loan application MicroTx workflow API token" "$MICROTX_CLIENT_ID" "$MICROTX_CLIENT_SECRET" \
    "$MICROTX_SCOPE" "microtx-workflow" "microtx-conductor-user,microtx-conductor-worker"
if [[ -n "$MICROTX_CONSOLE_CLIENT_SECRET" ]]; then
    check_authorization_code_client "MicroTx Console OIDC client" "$MICROTX_CONSOLE_CLIENT_ID" \
        "$MICROTX_CONSOLE_SCOPE" "$MICROTX_CONSOLE_REDIRECT_URI"
else
    skip "MicroTx Console OIDC client (not configured)"
fi

section "4. Security rejection checks"
check_invalid_machine_client_secret "Shared service" "$SERVICE_CLIENT_ID" "$SERVICE_CLIENT_SECRET" "$SERVICE_SCOPE"
check_invalid_machine_client_secret "Document ingest" "$DOCUMENT_INGEST_CLIENT_ID" \
    "$DOCUMENT_INGEST_CLIENT_SECRET" "$DOCUMENT_INGEST_SCOPE"
check_invalid_machine_client_secret "Document review" "$DOCUMENT_REVIEW_CLIENT_ID" \
    "$DOCUMENT_REVIEW_CLIENT_SECRET" "$DOCUMENT_REVIEW_SCOPE"
check_invalid_machine_client_secret "AI agent" "$AI_AGENT_CLIENT_ID" \
    "$AI_AGENT_CLIENT_SECRET" "$AI_AGENT_SCOPE"
check_invalid_machine_client_secret "MicroTx" "$MICROTX_CLIENT_ID" "$MICROTX_CLIENT_SECRET" "$MICROTX_SCOPE"

check_unauthorized_scope "Shared service" "$SERVICE_CLIENT_ID" "$SERVICE_CLIENT_SECRET" "microtx.workflow"
check_unauthorized_scope "Document ingest" "$DOCUMENT_INGEST_CLIENT_ID" \
    "$DOCUMENT_INGEST_CLIENT_SECRET" "microtx.workflow"
check_unauthorized_scope "Document review" "$DOCUMENT_REVIEW_CLIENT_ID" \
    "$DOCUMENT_REVIEW_CLIENT_SECRET" "microtx.workflow"
check_unauthorized_scope "AI agent" "$AI_AGENT_CLIENT_ID" \
    "$AI_AGENT_CLIENT_SECRET" "microtx.workflow"
check_unauthorized_scope "MicroTx" "$MICROTX_CLIENT_ID" "$MICROTX_CLIENT_SECRET" "cloudbank.internal"

if ! perform_basic_request "$BROWSER_CLIENT_ID" "$BROWSER_CLIENT_SECRET" \
        --request POST \
        --header "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "grant_type=client_credentials" \
        --data-urlencode "scope=cloudbank.read" \
        "$BASE_URL/oauth2/token"; then
    fail "Browser client rejects client credentials (request failed)"
elif [[ "$RESPONSE_STATUS" != "400" ]] ||
        ! body_contains '"error"[[:space:]]*:[[:space:]]*"unauthorized_client"'; then
    fail "Browser client rejects client credentials (expected HTTP 400 unauthorized_client)"
else
    pass "Browser client rejects client credentials"
fi

RESPONSE_BODY=""
ACCESS_TOKEN=""
JWT_PAYLOAD=""
printf '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
if [[ "$FAIL_COUNT" -eq 0 ]]; then
    printf 'Result: PASSED — %d checks passed, 0 failed\n' "$PASS_COUNT"
else
    printf 'Result: FAILED — %d checks passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT" >&2
fi
printf '%s\n' 'Security: passwords, client secrets, and raw JWTs were not displayed.'
if [[ "$FAIL_COUNT" -ne 0 ]]; then
    exit 1
fi
