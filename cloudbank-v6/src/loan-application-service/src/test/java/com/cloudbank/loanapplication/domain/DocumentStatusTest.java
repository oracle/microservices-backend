// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.domain;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class DocumentStatusTest {

    @Test
    void permitsIngestAndReviewTransitions() {
        assertThat(DocumentStatus.RECEIVED.canTransitionTo(DocumentStatus.EXTRACTED)).isTrue();
        assertThat(DocumentStatus.RECEIVED.canTransitionTo(DocumentStatus.FAILED_RETRYABLE)).isTrue();
        assertThat(DocumentStatus.FAILED_RETRYABLE.canTransitionTo(DocumentStatus.EXTRACTED)).isTrue();
        assertThat(DocumentStatus.EXTRACTED.canTransitionTo(DocumentStatus.VALIDATED)).isTrue();
        assertThat(DocumentStatus.EXTRACTED.canTransitionTo(DocumentStatus.NEEDS_REVIEW)).isTrue();
        assertThat(DocumentStatus.EXTRACTED.canTransitionTo(DocumentStatus.FAILED_RETRYABLE)).isTrue();
    }

    @Test
    void rejectsSkippedAndTerminalTransitions() {
        assertThat(DocumentStatus.RECEIVED.canTransitionTo(DocumentStatus.VALIDATED)).isFalse();
        assertThat(DocumentStatus.EXPECTED.canTransitionTo(DocumentStatus.EXTRACTED)).isFalse();
        assertThat(DocumentStatus.VALIDATED.canTransitionTo(DocumentStatus.NEEDS_REVIEW)).isFalse();
        assertThat(DocumentStatus.FAILED_FINAL.canTransitionTo(DocumentStatus.EXTRACTED)).isFalse();
        assertThat(DocumentStatus.EXTRACTED.canTransitionTo(null)).isFalse();
    }
}
