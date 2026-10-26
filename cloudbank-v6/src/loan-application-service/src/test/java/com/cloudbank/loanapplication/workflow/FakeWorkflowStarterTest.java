// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.workflow;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class FakeWorkflowStarterTest {

    private final FakeWorkflowStarter starter = new FakeWorkflowStarter();

    @Test
    void returnsSameWorkflowForSameIdempotencyKey() {
        WorkflowStarter.StartWorkflowCommand command = new WorkflowStarter.StartWorkflowCommand(
                "cloudbank-loan-origination", 1, "APP-1", "APP-1", "{}",
                "0123456789abcdef0123456789abcdef");

        assertThat(starter.start(command).workflowId())
                .isEqualTo(starter.start(command).workflowId());
    }
}
