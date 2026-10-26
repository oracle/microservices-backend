// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.domain;

public enum DocumentStatus {
    EXPECTED,
    RECEIVED,
    EXTRACTED,
    VALIDATED,
    NEEDS_REVIEW,
    FAILED_RETRYABLE,
    FAILED_FINAL;

    public boolean canTransitionTo(DocumentStatus target) {
        if (target == null) {
            return false;
        }
        return switch (this) {
            case RECEIVED -> target == EXTRACTED || target == FAILED_RETRYABLE || target == FAILED_FINAL;
            case FAILED_RETRYABLE -> target == EXTRACTED || target == FAILED_RETRYABLE || target == FAILED_FINAL;
            case EXTRACTED -> target == VALIDATED || target == NEEDS_REVIEW || target == FAILED_RETRYABLE
                    || target == FAILED_FINAL;
            case EXPECTED, VALIDATED, NEEDS_REVIEW, FAILED_FINAL -> false;
        };
    }
}
