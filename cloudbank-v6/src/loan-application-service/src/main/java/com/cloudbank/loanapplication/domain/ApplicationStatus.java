// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.domain;

import java.util.EnumSet;
import java.util.Map;
import java.util.Set;

public enum ApplicationStatus {
    SUBMITTED,
    DOCUMENTS_RECEIVED,
    PROCESSING,
    MANUAL_REVIEW,
    APPROVED,
    REJECTED,
    FAILED_RETRYABLE,
    RECOVERED,
    WITHDRAWN,
    EXPIRED;

    private static final Map<ApplicationStatus, Set<ApplicationStatus>> TRANSITIONS = Map.of(
            SUBMITTED, EnumSet.of(DOCUMENTS_RECEIVED, PROCESSING, WITHDRAWN),
            DOCUMENTS_RECEIVED, EnumSet.of(PROCESSING, WITHDRAWN),
            PROCESSING, EnumSet.of(MANUAL_REVIEW, APPROVED, REJECTED, FAILED_RETRYABLE),
            MANUAL_REVIEW, EnumSet.of(APPROVED, REJECTED, WITHDRAWN),
            FAILED_RETRYABLE, EnumSet.of(PROCESSING, RECOVERED, REJECTED));

    public boolean canTransitionTo(ApplicationStatus target) {
        return TRANSITIONS.getOrDefault(this, Set.of()).contains(target);
    }
}
