#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.
set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT/src/loan-application-service/lib/demo-intake.sh"
readonly PACKET="$ROOT/synthetic_data/customer_packets/demo_geocoded_loan"
readonly TEMPLATE="$PACKET/application.json"
test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' EXIT

build_demo_intake "$TEMPLATE" test-run-one AUTO false >"$test_dir/one.json"
build_demo_intake "$TEMPLATE" test-run-two DEFERRED false >"$test_dir/two.json"
build_demo_intake "$TEMPLATE" test-manual AUTO true >"$test_dir/manual.json"
jq -e '
    .scenarioId == "SMOKE-test-run-one" and .workflowStartMode == "AUTO" and
    .applicant.phoneToken == "smoke-phone-test-run-one" and
    .loan.requestedAmount == 5000 and .loan.requestedTermMonths == 24 and
    .applicant.address.postalCode == "21629" and
    ([.documents[].status] == ["EXPECTED", "EXPECTED"]) and
    ([.. | objects | select(has("applicationId") or has("documentId") or has("workflowId"))] | length == 0)
' "$test_dir/one.json" >/dev/null
jq -e --slurpfile first "$test_dir/one.json" '
    .workflowStartMode == "DEFERRED" and .scenarioId != $first[0].scenarioId and
    .applicant.emailToken != $first[0].applicant.emailToken and
    .applicant.address.addressToken != $first[0].applicant.address.addressToken
' "$test_dir/two.json" >/dev/null
jq -e '.scenarioName == "Manual Review: Employer Inconsistency"' "$test_dir/manual.json" >/dev/null
while IFS= read -r file; do [[ -s "$PACKET/$file" ]]; done < <(jq -r '.documents[].fileName' "$TEMPLATE")
[[ -s "$PACKET/manual-review/loan_application.pdf" ]]

jq '. + {applicationId:"APP-UNTRUSTED"}' "$TEMPLATE" >"$test_dir/invalid.json"
if validate_demo_application "$test_dir/invalid.json"; then
    printf 'FAIL: template supplied a canonical application ID\n' >&2; exit 1
fi
jq '.documents[0].fileName = "../outside.pdf"' "$TEMPLATE" >"$test_dir/invalid.json"
if validate_demo_application "$test_dir/invalid.json"; then
    printf 'FAIL: template allowed a PDF outside the packet\n' >&2; exit 1
fi

# Exercise the real geocoded entrypoint against a local downstream stub. No
# authorization, Kubernetes or workflow call is performed by this regression.
mkdir -p "$test_dir/entry/src/workflows" "$test_dir/entry/src/loan-application-service"
cp "$ROOT/src/workflows/start-geocoded-loan-oke.sh" "$test_dir/entry/src/workflows/"
cat >"$test_dir/entry/src/loan-application-service/smoke-test-obaas.sh" <<'STUB'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$@" >"$DEMO_CAPTURE.args"
printf '%s\n' "$LOAN_SMOKE_ADDRESS_JSON_FILE" >"$DEMO_CAPTURE.address"
[[ "$LOAN_SMOKE_STOP_AFTER_DISPATCH" == true && "$LOAN_SMOKE_VERIFY_GEO" == true ]]
STUB
chmod 700 "$test_dir/entry/src/loan-application-service/smoke-test-obaas.sh"
DEMO_CAPTURE="$test_dir/default" bash "$test_dir/entry/src/workflows/start-geocoded-loan-oke.sh" \
    synthetic-context --namespace synthetic-ns --application-file "$TEMPLATE" >"$test_dir/entry.out"
grep -Fxq -- '--application-file' "$test_dir/default.args"
grep -Fxq -- "$TEMPLATE" "$test_dir/default.args"
[[ ! -s "$test_dir/default.address" || "$(cat "$test_dir/default.address")" == "" ]]
grep -Fq -- 'Postal code: 21629' "$test_dir/entry.out"

jq '.applicant.address | del(.addressToken) | .postalCode = "21630"' "$TEMPLATE" >"$test_dir/address.json"
DEMO_CAPTURE="$test_dir/override" bash "$test_dir/entry/src/workflows/start-geocoded-loan-oke.sh" \
    synthetic-context --application-file "$TEMPLATE" --address-file "$test_dir/address.json" >"$test_dir/entry.out"
[[ "$(cat "$test_dir/override.address")" == "$test_dir/address.json" ]]
grep -Fq -- 'Postal code: 21630' "$test_dir/entry.out"

printf 'PASS: shared intake, ready PDFs, safe filenames and CLI packet/address forwarding.\n'
