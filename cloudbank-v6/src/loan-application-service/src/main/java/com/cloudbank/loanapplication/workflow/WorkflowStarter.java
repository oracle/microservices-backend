// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.workflow;

public interface WorkflowStarter {

    WorkflowExecution start(StartWorkflowCommand command);

    record StartWorkflowCommand(
            String workflowName,
            int workflowVersion,
            String idempotencyKey,
            String applicationId,
            String payload,
            String traceId) {
    }

    record WorkflowExecution(String workflowId, String status) {
    }
}
