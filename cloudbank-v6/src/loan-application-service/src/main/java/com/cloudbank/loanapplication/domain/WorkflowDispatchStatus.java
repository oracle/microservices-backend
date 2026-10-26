// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.domain;

public enum WorkflowDispatchStatus {
    WAITING_FOR_DOCUMENTS,
    DEFERRED,
    PENDING,
    IN_PROGRESS,
    STARTED,
    FAILED_RETRYABLE,
    FAILED_FINAL,
    CANCELLED
}
