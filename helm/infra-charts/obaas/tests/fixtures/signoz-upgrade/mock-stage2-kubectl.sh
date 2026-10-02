#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.

set -euo pipefail
SCENARIO="${MOCK_SCENARIO:-success}"
last_argument="${!#}"

if [[ "$1" == get && "$2" == secret ]]; then
  [[ "${SCENARIO}" == no-marker ]] && exit 1
  [[ "$*" != *go-template* ]] && exit 0
  case "$*" in
    *'"workflow"'*) echo 'signoz-0.142.1-two-stage' ;;
    *'"stage"'*) echo 'stage1' ;;
    *'"status"'*) [[ "${SCENARIO}" == malformed-marker ]] || echo 'complete' ;;
    *'"releaseName"'*) echo 'obaas' ;;
    *'"namespace"'*) echo 'obaas' ;;
    *'"helmRevision"'*) [[ "${SCENARIO}" == stale-marker ]] && echo 6 || echo 7 ;;
    *'"targetVersion"'*) echo '0.142.1' ;;
    *'"clickhouseVersion"'*) echo '25.12.5.44' ;;
    *'"snapshots"'*) printf 'clickhouse\tch-pvc\tuid-ch-pvc\tch-snap\nsignoz\tsignoz-pvc\tuid-signoz-pvc\tsignoz-snap\nzookeeper\tzk-pvc\tuid-zk-pvc\tzk-snap' ;;
    *) exit 1 ;;
  esac
  exit 0
fi

if [[ "$1" == get && "$2" == pvc ]]; then
  [[ "${SCENARIO}" == mismatched-pvc && "$3" == signoz-pvc ]] && echo replacement-uid || echo "uid-$3"
  exit 0
fi

if [[ "$1" == get && "$2" == volumesnapshot.snapshot.storage.k8s.io ]]; then
  snapshot="$3"
  [[ "${SCENARIO}" == deleted-snapshot && "${snapshot}" == signoz-snap ]] && exit 1
  [[ "$*" != *jsonpath* ]] && exit 0
  case "${last_argument}" in
    *readyToUse*) echo true ;;
    *source-pvc-uid*) echo "uid-${snapshot%-snap}-pvc" ;;
    *source-pvc*) echo "${snapshot%-snap}-pvc" ;;
    *helm-revision*) echo 7 ;;
    *) exit 1 ;;
  esac
  exit 0
fi

if [[ "$1" == wait ]]; then exit 0; fi
if [[ "$1" == get && "$2" == pods ]]; then echo clickhouse-0; exit 0; fi
if [[ "$1" == get && "$2" == pod ]]; then
  [[ "${SCENARIO}" == wrong-clickhouse ]] && echo docker.io/clickhouse/clickhouse-server:25.5.6 || echo docker.io/clickhouse/clickhouse-server:25.12.5
  exit 0
fi
if [[ "$1" == get && "$2" == clickhouseinstallations.clickhouse.altinity.com ]]; then echo obaas-clickhouse; exit 0; fi
if [[ "$1" == get && "$2" == clickhouseinstallation.clickhouse.altinity.com ]]; then echo password; exit 0; fi
if [[ "$1" == exec ]]; then
  [[ "${SCENARIO}" == wrong-clickhouse ]] && echo 25.5.6.1 || echo 25.12.5.44
  exit 0
fi
echo "Unexpected invocation: $*" >&2
exit 1
