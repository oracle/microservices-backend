#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.

set -euo pipefail
SCENARIO="${MOCK_SCENARIO:-success}"
if [[ "$1" == wait ]]; then
  [[ "${SCENARIO}" == migration-failed && "$2" == job/signoz-telemetrystore-migrator ]] && exit 1
  [[ "${SCENARIO}" == setup-failed && "$2" == job/*-signoz-setup ]] && exit 1
  exit 0
fi
if [[ "$1" == get && "$2" == pods ]]; then
  if [[ "$*" == *component=signoz* ]]; then
    [[ "${SCENARIO}" == wrong-signoz ]] && echo docker.io/signoz/signoz:v0.113.0 || echo docker.io/signoz/signoz:v0.142.1
  else
    [[ "${SCENARIO}" == wrong-collector ]] && echo docker.io/signoz/signoz-otel-collector:v0.144.1 || echo docker.io/signoz/signoz-otel-collector:v0.144.10
  fi
  exit 0
fi
exit 1
