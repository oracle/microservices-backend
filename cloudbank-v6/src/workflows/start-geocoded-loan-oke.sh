#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly OKE_SMOKE_TEST="$SCRIPT_DIR/../loan-application-service/smoke-test-obaas.sh"

KUBECTL_CONTEXT=""
OBAAS_NAMESPACE=""
ADDRESS_JSON_FILE=""
APPLICATION_JSON_FILE="${LOAN_SMOKE_APPLICATION_JSON_FILE:-$SCRIPT_DIR/../../synthetic_data/customer_packets/demo_geocoded_loan/application.json}"

usage() {
    cat <<EOF
Usage: ${0##*/} <kubectl-context> [--namespace NAME] [--application-file FILE] [--address-file FILE]

Creates a synthetic loan application using the address in a JSON file,
uploads two synthetic PDFs, and starts cloudbank-loan-origination v1 on OKE.
After document review, the workflow calls ai-agent-service and
geographic-risk-service. No coordinates are required: geographic-risk-service
uses Oracle GCDR to geocode an application without stored geometry.

  --namespace NAME    OBaaS application namespace (auto-detected by default)
  --address-file FILE Optional address override (default: the application packet address)
  --application-file FILE Intake JSON with ready PDFs in its directory
  -h, --help          Show this help

The script prints the address and reads test credentials from the environment
or the repository .env file (or CLOUDBANK_ENV_FILE) without prompting. The
application and address remain in the database after this script exits. It waits
for a geographic-risk evaluation and checks that geocoding returned a point.
LOAN_SMOKE_GEO_WAIT_SECONDS controls the wait (default: 180 seconds). The
workflow may continue after this check completes.
EOF
}

die() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 2
}

validate_address_file() {
    local invalid_fields
    local address_source="$1"

    [[ -r "$address_source" ]] || die "address JSON source is not readable"
    invalid_fields="$(jq -r '
        (if type == "object" and has("applicant") then .applicant.address | del(.addressToken) else . end) |
        def text_between($minimum; $maximum):
            if type == "string" then length >= $minimum and length <= $maximum else false end;
        def matches($pattern):
            if type == "string" then test($pattern) else false end;
        if type != "object" then "root (JSON object required)"
        else [
            (if (keys - ["addressLine", "locality", "jurisdictionCode", "countryCode", "postalCode"]) == []
             then empty else "unsupported field" end),
            (if (.addressLine | text_between(1; 300)) then empty else "addressLine (1-300 characters)" end),
            (if (.locality | text_between(1; 120)) then empty else "locality (1-120 characters)" end),
            (if (.postalCode | text_between(0; 20)) then empty else "postalCode (at most 20 characters)" end),
            (if (.countryCode | matches("^[A-Z]{2}$")) then empty else "countryCode (two uppercase letters)" end),
            (if (.jurisdictionCode | matches("^[A-Z0-9_-]{2,20}$"))
             then empty else "jurisdictionCode (2-20 uppercase letters, digits, _ or -)" end)
        ] | join("; ") end
    ' "$address_source" 2>/dev/null)" || die "address source is not valid JSON"
    [[ -z "$invalid_fields" ]] || die "invalid address fields: $invalid_fields"
}

parse_args() {
    [[ $# -ge 1 ]] || { usage >&2; exit 2; }
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        usage
        exit 0
    fi
    KUBECTL_CONTEXT="$1"
    shift
    [[ -n "$KUBECTL_CONTEXT" && "$KUBECTL_CONTEXT" != -* ]] ||
        die "specify a kubectl context"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --namespace)
                [[ $# -ge 2 && -n "$2" && "$2" != -* ]] ||
                    die "--namespace requires a value"
                OBAAS_NAMESPACE="$2"
                shift 2
                ;;
            --address-file)
                [[ $# -ge 2 && -n "$2" && "$2" != -* ]] ||
                    die "--address-file requires a file path"
                ADDRESS_JSON_FILE="$2"
                shift 2
                ;;
            --application-file)
                [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || die "--application-file requires a path"
                APPLICATION_JSON_FILE="$2"
                shift 2
                ;;
            --from-env | --yes)
                shift
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            *) die "unknown option: $1" ;;
        esac
    done
}

main() {
    local -a oke_args=()

    parse_args "$@"
    [[ -x "$OKE_SMOKE_TEST" ]] || die "OKE smoke test is not executable"
    command -v jq >/dev/null 2>&1 || die "jq is required"
    local address_source="${ADDRESS_JSON_FILE:-$APPLICATION_JSON_FILE}"
    validate_address_file "$address_source"
    printf 'Address from %s:\n' "$address_source"
    jq -r '
        (if has("applicant") then .applicant.address else . end) |
        "  Street and house number: \(.addressLine)\n" +
        "  City or locality: \(.locality)\n" +
        "  Postal code: \(.postalCode)\n" +
        "  ISO country code: \(.countryCode)\n" +
        "  CloudBank jurisdiction code: \(.jurisdictionCode)"
    ' "$address_source"

    if [[ -n "$OBAAS_NAMESPACE" ]]; then
        oke_args+=(--namespace "$OBAAS_NAMESPACE")
    fi
    oke_args+=(--from-env --application-file "$APPLICATION_JSON_FILE")

    LOAN_SMOKE_ADDRESS_JSON_FILE="$ADDRESS_JSON_FILE" \
    LOAN_SMOKE_STOP_AFTER_DISPATCH=true \
    LOAN_SMOKE_VERIFY_GEO=true \
        "$OKE_SMOKE_TEST" "$KUBECTL_CONTEXT" "${oke_args[@]}"
}

main "$@"
