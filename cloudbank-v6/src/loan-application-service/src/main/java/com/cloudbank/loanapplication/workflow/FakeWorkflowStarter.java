// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.workflow;

import java.nio.charset.StandardCharsets;
import java.util.UUID;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(prefix = "cloudbank.workflow", name = "mode", havingValue = "fake", matchIfMissing = true)
public class FakeWorkflowStarter implements WorkflowStarter {

    @Override
    public WorkflowExecution start(StartWorkflowCommand command) {
        String workflowId = "fake-" + UUID.nameUUIDFromBytes(
                command.idempotencyKey().getBytes(StandardCharsets.UTF_8));
        return new WorkflowExecution(workflowId, "STARTED");
    }
}
