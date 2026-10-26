#!/usr/bin/env bash
# Run inside the one-shot bootstrap Job. Never log credentials or identity values.
set -euo pipefail
set +x

fail() { printf 'ERROR: lab owner bootstrap failed (%s).\n' "$1" >&2; exit 1; }
[[ "${LAB_ADMIN_PRINCIPAL_ID:-}" =~ ^[A-Za-z0-9_-]{1,80}$ ]] || fail invalid-identity
[[ "${LAB_ADMIN_ISSUER:-}" =~ ^https?://[A-Za-z0-9.-]+(:[0-9]+)?$ ]] || fail invalid-issuer
[[ "${DB_ADMIN_USERNAME:-}" =~ ^[A-Za-z][A-Za-z0-9_\$#]*$ ]] || fail invalid-db-user
[[ "${DB_SERVICE:-}" =~ ^[A-Za-z0-9_.-]+$ ]] || fail invalid-db-service
[[ -n "${DB_ADMIN_PASSWORD:-}" ]] || fail missing-db-password
case "$DB_ADMIN_PASSWORD" in
    *'"'* | *$'\n'* | *$'\r'*) fail invalid-db-password ;;
esac

if output="$(sql -S /nolog 2>&1 <<SQL
WHENEVER OSERROR EXIT FAILURE ROLLBACK
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET ECHO OFF
SET VERIFY OFF
SET DEFINE OFF
SET FEEDBACK OFF
SET HEADING OFF
SET SERVEROUTPUT ON
CONNECT ${DB_ADMIN_USERNAME}/"${DB_ADMIN_PASSWORD}"@${DB_SERVICE}
VARIABLE lab_admin_principal_id VARCHAR2(80)
VARIABLE lab_admin_issuer VARCHAR2(300)
BEGIN
  :lab_admin_principal_id := '${LAB_ADMIN_PRINCIPAL_ID}';
  :lab_admin_issuer := '${LAB_ADMIN_ISSUER}';
END;
/
@/bootstrap/provision.sql
COMMIT;
EXIT SUCCESS
SQL
)"; then
    status=0
else
    status=$?
fi
unset DB_ADMIN_PASSWORD LAB_ADMIN_PRINCIPAL_ID
if [[ "$status" -ne 0 ]] || printf '%s\n' "$output" | grep -Eq 'ORA-[0-9]+|SP2-[0-9]+|Connection failed|Not connected'; then
    # Report numeric error codes only; SQLcl errors can contain private values.
    printf '%s\n' "$output" | grep -Eo '(ORA|SP2)-[0-9]+' | sort -u >&2 || true
    fail sql-execution
fi
printf '%s\n' "$output" | grep -Eq '^LAB_ADMIN_APPLICATIONS_TOTAL=[0-9]+$' || fail missing-verification
printf '%s\n' "$output" | grep -Eq '^LAB_ADMIN_APPLICATIONS_VISIBLE=[0-9]+$' || fail missing-verification
printf '%s\n' "$output" | grep -E '^LAB_ADMIN_APPLICATIONS_(TOTAL|VISIBLE)=[0-9]+$'
printf 'LAB_ADMIN_BOOTSTRAP_OK\n'
