// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.cloudbank.loanapplication.domain.ApplicationStatus;
import org.junit.jupiter.api.Test;

class ApplicationStatusTest {

    @Test
    void allowsOnlyDefinedStatusTransitions() {
        assertThat(ApplicationStatus.SUBMITTED.canTransitionTo(ApplicationStatus.PROCESSING)).isTrue();
        assertThat(ApplicationStatus.PROCESSING.canTransitionTo(ApplicationStatus.MANUAL_REVIEW)).isTrue();
        assertThat(ApplicationStatus.APPROVED.canTransitionTo(ApplicationStatus.PROCESSING)).isFalse();
        assertThat(ApplicationStatus.REJECTED.canTransitionTo(ApplicationStatus.APPROVED)).isFalse();
    }
}
