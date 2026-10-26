#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

# application.json is a reusable template. Canonical application/document IDs
# come only from intake; per-run synthetic correlation values are fresh.
validate_demo_application() {
    jq -e '
        type == "object" and
        ((keys - ["scenarioId", "scenarioName", "applicant", "loan", "documents"]) == []) and
        (.scenarioId | type == "string" and length > 0) and
        (.scenarioName | type == "string" and length > 0) and
        (.applicant | type == "object") and (.loan | type == "object") and
        ([.applicant.phoneToken, .applicant.emailToken, .applicant.address.addressToken] |
            all(.[]; type == "string" and length > 0)) and
        (.documents | type == "array" and length == 2) and
        ([.documents[].fileName] | unique | length == 2) and
        ([.documents[].documentType] | sort == ["LOAN_APPLICATION", "PAY_STATEMENT"]) and
        all(.documents[];
            ((keys - ["documentType", "fileName", "required"]) == []) and
            (.fileName | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9_.-]*\\.pdf$")) and
            (.required | type == "boolean"))
    ' "$1" >/dev/null
}

build_demo_intake() {
    local application_file="$1" run_id="$2" start_mode="$3" manual_review="$4"
    validate_demo_application "$application_file" || return 1
    jq -c --arg runId "$run_id" --arg startMode "$start_mode" --arg manualReview "$manual_review" '
        .scenarioId += "-" + $runId |
        .applicant.phoneToken += "-" + $runId |
        .applicant.emailToken += "-" + $runId |
        .applicant.address.addressToken += "-" + $runId |
        .workflowStartMode = $startMode |
        .documents |= map(. + {status:"EXPECTED", mediaType:"application/pdf"}) |
        if $manualReview == "true" then .scenarioName = "Manual Review: Employer Inconsistency" else . end
    ' "$application_file"
}
