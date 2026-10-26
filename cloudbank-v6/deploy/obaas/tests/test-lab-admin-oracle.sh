#!/usr/bin/env bash
# Oracle regression tests for the real provisioning SQL. Every test rolls back.
# Uses the configured lab and its bootstrap Job; no application/user is created.
set -Eeuo pipefail
TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_SCRIPT_DIR/../provision-lab-admin.sh"
umask 077
LAB_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cloudbank-lab-admin-sql-test.XXXXXX")"
trap lab_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
lab_load_target
lab_lookup_identity
lab_render

# Execute the production PL/SQL block through dynamic binds, catching expected
# failures. The outer rollback also removes the provisional first grant.
cat >"$LAB_WORK_DIR/regression.sql" <<'SQL'
DECLARE
  l_sql CLOB := q'~
SQL
sed -n '/^DECLARE$/,/^END;$/p' "$LAB_ROOT/src/schema/admin/003-lab-admin-access.sql" >>"$LAB_WORK_DIR/regression.sql"
cat >>"$LAB_WORK_DIR/regression.sql" <<'SQL'
~';
  l_id VARCHAR2(80) := :lab_admin_principal_id;
  l_issuer VARCHAR2(300) := :lab_admin_issuer;
  l_original_id VARCHAR2(80) := l_id;
  l_original_issuer VARCHAR2(300) := l_issuer;
  l_other_principals NUMBER;
  l_other_grants NUMBER;
  l_count NUMBER;
  PROCEDURE run_case(p_expected NUMBER) IS
  BEGIN
    SAVEPOINT lab_admin_access;
    BEGIN
      EXECUTE IMMEDIATE l_sql USING l_id, l_issuer;
      IF p_expected != 0 THEN RAISE_APPLICATION_ERROR(-20201, 'Expected provisioning rejection'); END IF;
    EXCEPTION
      WHEN OTHERS THEN IF SQLCODE != p_expected THEN RAISE; END IF;
    END;
  END;
BEGIN
  SAVEPOINT lab_regression_start;
  SELECT COUNT(*) INTO l_other_principals FROM cloudbank.cb_app_principal WHERE principal_id != l_id;
  SELECT COUNT(*) INTO l_other_grants FROM cloudbank.cb_app_role_grant r
    JOIN cloudbank.cb_app_principal p ON p.principal_sk=r.principal_sk WHERE p.principal_id != l_id;
  run_case(0);
  run_case(0);
  SELECT COUNT(*) INTO l_count FROM cloudbank.cb_app_role_grant r
    JOIN cloudbank.cb_app_principal p ON p.principal_sk=r.principal_sk
    WHERE p.principal_id=l_id AND r.role_code='ADMIN';
  IF l_count != 1 THEN RAISE_APPLICATION_ERROR(-20202, 'Idempotency assertion failed'); END IF;

  SAVEPOINT lab_regression_case;
  UPDATE cloudbank.cb_app_role_grant SET grant_status='REVOKED'
    WHERE principal_sk=(SELECT principal_sk FROM cloudbank.cb_app_principal WHERE principal_id=l_id) AND role_code='ADMIN';
  run_case(-20104);
  ROLLBACK TO lab_regression_case;

  SAVEPOINT lab_regression_case;
  UPDATE cloudbank.cb_app_role_grant SET granted_at=SYSTIMESTAMP-INTERVAL '2' DAY,
    expires_at=SYSTIMESTAMP-INTERVAL '1' DAY
    WHERE principal_sk=(SELECT principal_sk FROM cloudbank.cb_app_principal WHERE principal_id=l_id) AND role_code='ADMIN';
  run_case(-20104);
  ROLLBACK TO lab_regression_case;

  SAVEPOINT lab_regression_case;
  UPDATE cloudbank.cb_app_principal SET status='DISABLED' WHERE principal_id=l_id;
  run_case(-20103);
  ROLLBACK TO lab_regression_case;

  l_issuer := 'http://wrong-issuer';
  run_case(-20103);
  l_issuer := l_original_issuer;
  l_id := l_original_id || '-other';
  run_case(-20102);
  l_id := l_original_id;

  SELECT COUNT(*) INTO l_count FROM cloudbank.cb_app_principal WHERE principal_id != l_id;
  IF l_count != l_other_principals THEN RAISE_APPLICATION_ERROR(-20203, 'Other principals changed'); END IF;
  SELECT COUNT(*) INTO l_count FROM cloudbank.cb_app_role_grant r
    JOIN cloudbank.cb_app_principal p ON p.principal_sk=r.principal_sk WHERE p.principal_id != l_id;
  IF l_count != l_other_grants THEN RAISE_APPLICATION_ERROR(-20204, 'Other grants changed'); END IF;
  ROLLBACK TO lab_regression_start;
EXCEPTION
  WHEN OTHERS THEN ROLLBACK; RAISE;
END;
/
SQL
jq --rawfile sql "$LAB_WORK_DIR/regression.sql" '.data["provision.sql"]=$sql' \
    "$LAB_WORK_DIR/config.json" >"$LAB_WORK_DIR/test-config.json"
mv "$LAB_WORK_DIR/test-config.json" "$LAB_WORK_DIR/config.json"
kubectl --context "$LAB_CONTEXT" -n "$LAB_NAMESPACE" create -f "$LAB_WORK_DIR/config.json" >/dev/null
LAB_CREATED_CONFIG=true
kubectl --context "$LAB_CONTEXT" -n "$LAB_NAMESPACE" create -f "$LAB_WORK_DIR/identity.json" >/dev/null
LAB_CREATED_IDENTITY=true
kubectl --context "$LAB_CONTEXT" -n "$LAB_NAMESPACE" create -f "$LAB_WORK_DIR/job.json" >/dev/null
LAB_CREATED_JOB=true
completed=false
if kubectl --context "$LAB_CONTEXT" -n "$LAB_NAMESPACE" wait --for=condition=complete "job/$LAB_NAME" --timeout=8m; then completed=true; fi
kubectl --context "$LAB_CONTEXT" -n "$LAB_NAMESPACE" logs "job/$LAB_NAME" -c provisioner >"$LAB_WORK_DIR/test-result.log" 2>&1 || true
if [[ "$completed" != true ]] || ! grep -qx LAB_ADMIN_BOOTSTRAP_OK "$LAB_WORK_DIR/test-result.log"; then
    grep -Eo '(ORA|SP2)-[0-9]+' "$LAB_WORK_DIR/test-result.log" | sort -u >&2 || true
    lab_fail 'Oracle rollback regression tests failed.'
fi
printf 'PASS: Oracle provisioning, idempotency, revoked/expired/disabled guards, identity mismatch, and preservation of other principals. All test changes rolled back.\n'
