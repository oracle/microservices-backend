#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

# Compare semantic versions numerically, including prerelease precedence.
# Build metadata does not affect precedence; callers retain the full appVersion
# when selecting the matching application chart. No GNU sort or new dependency
# is required on macOS.
obaas_version_at_least() {
    local current="$1"
    local minimum="${2:-2.1.0}"
    local pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'

    [[ "$current" =~ $pattern && "$minimum" =~ $pattern ]] || return 1
    LC_ALL=C awk -v current="$current" -v minimum="$minimum" '
        function number_compare(a, b) {
            if (length(a) != length(b)) return length(a) > length(b) ? 1 : -1
            if (("x" a) == ("x" b)) return 0
            return ("x" a) > ("x" b) ? 1 : -1
        }
        function valid_prerelease(value, parts, count, i) {
            count = split(value, parts, /\./)
            for (i = 1; i <= count; i++) {
                if (parts[i] ~ /^[0-9]+$/ && length(parts[i]) > 1 && substr(parts[i], 1, 1) == "0") return 0
            }
            return 1
        }
        function prerelease_compare(a, b, left, right, left_count, right_count, count, i, left_numeric, right_numeric) {
            if (("x" a) == ("x" b)) return 0
            if (a == "") return 1
            if (b == "") return -1
            left_count = split(a, left, /\./)
            right_count = split(b, right, /\./)
            count = left_count < right_count ? left_count : right_count
            for (i = 1; i <= count; i++) {
                if (("x" left[i]) == ("x" right[i])) continue
                left_numeric = left[i] ~ /^[0-9]+$/
                right_numeric = right[i] ~ /^[0-9]+$/
                if (left_numeric && right_numeric) return number_compare(left[i], right[i])
                if (left_numeric != right_numeric) return left_numeric ? -1 : 1
                return ("x" left[i]) > ("x" right[i]) ? 1 : -1
            }
            if (left_count == right_count) return 0
            return left_count > right_count ? 1 : -1
        }
        BEGIN {
            sub(/\+.*/, "", current)
            sub(/\+.*/, "", minimum)
            current_dash = index(current, "-")
            minimum_dash = index(minimum, "-")
            current_pre = current_dash ? substr(current, current_dash + 1) : ""
            minimum_pre = minimum_dash ? substr(minimum, minimum_dash + 1) : ""
            if (!valid_prerelease(current_pre) || !valid_prerelease(minimum_pre)) exit 1
            split(current_dash ? substr(current, 1, current_dash - 1) : current, current_parts, /\./)
            split(minimum_dash ? substr(minimum, 1, minimum_dash - 1) : minimum, minimum_parts, /\./)
            for (i = 1; i <= 3; i++) {
                comparison = number_compare(current_parts[i], minimum_parts[i])
                if (comparison != 0) exit comparison > 0 ? 0 : 1
            }
            exit prerelease_compare(current_pre, minimum_pre) >= 0 ? 0 : 1
        }
    '
}

validate_obaas_application_chart_transition() {
    local release="$1"
    local installed="$2"
    local target="$3"

    obaas_version_at_least "$installed" ||
        die "existing '$release' chart appVersion '$installed' must be a semantic version >= 2.1.0"
    obaas_version_at_least "$target" "$installed" ||
        die "existing '$release' chart appVersion '$installed' is newer than OBaaS '$target'; automatic chart downgrades are not supported"
    if [[ "$installed" != "$target" ]]; then
        info "Application chart '$release' will move from appVersion $installed to $target after chart validation."
    fi
}
