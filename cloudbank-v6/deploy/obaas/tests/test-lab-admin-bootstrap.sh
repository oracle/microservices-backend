#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
mkdir -p "$ROOT/.cloudbank-local"
TEST_DIR="$(mktemp -d "$ROOT/.cloudbank-local/lab-admin-test.XXXXXX")"
trap 'rm -rf -- "$TEST_DIR"' EXIT
umask 077
touch "$TEST_DIR/kubeconfig"
cat >"$TEST_DIR/test.env" <<EOF
CLOUDBANK_KUBECONFIG_PATH=$TEST_DIR/kubeconfig
MICROTX_NAMESPACE=test
AZN_ISSUER_URI=http://localhost:8080
IMAGE_PULL_SECRET=test-pull
AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD=synthetic-password-for-tests
EOF

for scenario in good wrong-role duplicate wrong-issuer job-failed; do
    (
        export CLOUDBANK_ENV_FILE="$TEST_DIR/test.env"
        source "$ROOT/deploy/obaas/provision-lab-admin.sh"
        LAB_WORK_DIR="$TEST_DIR/$scenario"
        mkdir -p "$LAB_WORK_DIR"
        trap lab_cleanup EXIT
        kubectl() {
            case "$*" in
                'config current-context') printf test-context ;;
                *'get deployment azn-server -o json')
                    printf '%s' '{"spec":{"template":{"spec":{"containers":[{"env":[{"name":"AZN_ISSUER_URI","value":"http://localhost:8080"},{"name":"AZN_LIQUIBASE_USERNAME","valueFrom":{"secretKeyRef":{"name":"test-db","key":"username"}}},{"name":"AZN_LIQUIBASE_PASSWORD","valueFrom":{"secretKeyRef":{"name":"test-db","key":"password"}}}],"volumeMounts":[{"name":"wallet","mountPath":"/oracle/tnsadmin"}]}],"volumes":[{"name":"wallet","secret":{"secretName":"test-wallet"}}]}}}}' ;;
                *'port-forward '*) printf 'Forwarding from 127.0.0.1:51234 -> 8080\n'; exec sleep 30 ;;
                *'get deployment loan-application-service -o jsonpath='*) printf 'registry.example/lab/cloudbank-ai/loan-application-service:release-1' ;;
                *'create --dry-run=server '*) : ;;
                *'create -f '*) printf '%s\n' "$*" >>"$TEST_DIR/creates" ;;
                *'wait --for=condition=complete '*) [[ "$scenario" != job-failed ]] ;;
                *'logs job/'*)
                    if [[ "$scenario" == job-failed ]]; then
                        printf 'ORA-20104: private-diagnostic-value\n'
                    else
                        printf 'private-diagnostic-value\nLAB_ADMIN_APPLICATIONS_TOTAL=3\nLAB_ADMIN_APPLICATIONS_VISIBLE=3\nLAB_ADMIN_BOOTSTRAP_OK\n'
                    fi ;;
                *'delete '*) : ;;
                *) printf 'Unexpected mocked Kubernetes call\n' >&2; return 1 ;;
            esac
        }
        curl() {
            if [[ "$*" == *openid-configuration* ]]; then
                if [[ "$scenario" == wrong-issuer ]]; then printf '{"issuer":"http://wrong-issuer"}';
                else printf '{"issuer":"http://localhost:8080"}'; fi
            else
                # The credential is supplied only on stdin, never in arguments.
                [[ "$*" != *synthetic-password* ]]
                cat >/dev/null
                case "$scenario" in
                    wrong-role) printf '[{"username":"obaas-admin","principalId":"test-admin","roles":"ROLE_ADMINISTRATOR"}]' ;;
                    duplicate) printf '[{"username":"obaas-admin","principalId":"test-admin","roles":"ROLE_ADMIN"},{"username":"obaas-admin","principalId":"another-id","roles":"ROLE_ADMIN"}]' ;;
                    *) printf '[{"username":"obaas-admin","principalId":"test-admin","roles":"ROLE_ADMIN,ROLE_USER"},{"username":"obaas-admin-other","principalId":"not-selected","roles":"ROLE_ADMIN"}]' ;;
                esac
            fi
        }
        lab_load_target
        lab_lookup_identity
        [[ "$LAB_PRINCIPAL_ID" == test-admin ]]
        lab_render
        jq -e '.spec.template.spec.automountServiceAccountToken == false and
            (.spec.template.spec.containers[0].env | map(select(.name=="DB_ADMIN_PASSWORD"))[0].valueFrom.secretKeyRef.name == "test-db") and
            (.spec.template.spec.containers[0].image == "registry.example/lab/cloudbank-ai/cloudbank-schema-init:release-1")' "$LAB_WORK_DIR/job.json" >/dev/null
        LAB_ASSUME_YES=true
        lab_apply
    ) >"$TEST_DIR/$scenario.out" 2>&1 && status=0 || status=$?
    if [[ "$scenario" == good ]]; then
        [[ "$status" -eq 0 ]]
        grep -q '^SUCCESS:' "$TEST_DIR/$scenario.out"
    else
        [[ "$status" -ne 0 ]] || { printf 'FAIL: scenario %s was accepted\n' "$scenario"; exit 1; }
    fi
    if grep -Eq 'synthetic-password|test-admin|private-diagnostic-value' "$TEST_DIR/$scenario.out"; then
        printf 'FAIL: sensitive values escaped the safe report\n' >&2
        exit 1
    fi
done

mkdir "$TEST_DIR/bin"
cat >"$TEST_DIR/bin/sql" <<'SH'
#!/usr/bin/env bash
cat >"$SQL_INPUT"
case "$SQL_SCENARIO" in
    good) printf 'LAB_ADMIN_APPLICATIONS_TOTAL=3\nLAB_ADMIN_APPLICATIONS_VISIBLE=3\n' ;;
    error) printf 'ORA-20104: private-diagnostic-value\n'; exit 1 ;;
    silent-error) printf 'ORA-20103: private-diagnostic-value\n' ;;
    missing-verification) printf 'Connected.\n' ;;
esac
SH
chmod +x "$TEST_DIR/bin/sql"
for scenario in good error silent-error missing-verification; do
    env PATH="$TEST_DIR/bin:$PATH" SQL_INPUT="$TEST_DIR/sql-input" SQL_SCENARIO="$scenario" \
        LAB_ADMIN_PRINCIPAL_ID=test-admin LAB_ADMIN_ISSUER=http://localhost:8080 \
        DB_ADMIN_USERNAME=ADMIN DB_ADMIN_PASSWORD=synthetic-password DB_SERVICE=test_high \
        bash "$ROOT/deploy/obaas/lib/run-lab-admin-bootstrap.sh" \
        >"$TEST_DIR/runner-$scenario.out" 2>&1 && status=0 || status=$?
    if [[ "$scenario" == good ]]; then
        [[ "$status" -eq 0 ]]
        grep -qx LAB_ADMIN_BOOTSTRAP_OK "$TEST_DIR/runner-$scenario.out"
        grep -q '^SET ECHO OFF' "$TEST_DIR/sql-input"
        grep -q '^COMMIT;' "$TEST_DIR/sql-input"
    else
        [[ "$status" -ne 0 ]]
    fi
    if grep -Eq 'synthetic-password|test-admin|private-diagnostic-value' "$TEST_DIR/runner-$scenario.out"; then
        printf 'FAIL: SQLcl details escaped the safe report\n' >&2
        exit 1
    fi
done
printf 'PASS: lab owner identity checks, safe Job rendering, failure propagation, and SQLcl output redaction.\n'
