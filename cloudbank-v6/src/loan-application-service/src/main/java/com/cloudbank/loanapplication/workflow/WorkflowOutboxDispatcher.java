// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.workflow;

import com.cloudbank.loanapplication.persistence.LoanApplicationRepository;
import com.cloudbank.loanapplication.persistence.LoanRecords.WorkflowRow;
import com.cloudbank.loanapplication.workflow.MicroTxWorkflowStarter.WorkflowStartException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.HttpServerErrorException;
import org.springframework.web.client.ResourceAccessException;

@Component
public class WorkflowOutboxDispatcher {

    private final LoanApplicationRepository repository;
    private final WorkflowStarter workflowStarter;
    private final TransactionTemplate transactions;
    private final int maxAttempts;

    public WorkflowOutboxDispatcher(LoanApplicationRepository repository, WorkflowStarter workflowStarter,
            TransactionTemplate transactions,
            @Value("${cloudbank.workflow.max-dispatch-attempts:5}") int maxAttempts) {
        this.repository = repository;
        this.workflowStarter = workflowStarter;
        this.transactions = transactions;
        this.maxAttempts = Math.max(1, maxAttempts);
    }

    @Scheduled(fixedDelayString = "${cloudbank.workflow.dispatch-delay-ms:1000}")
    public void dispatchOne() {
        WorkflowRow row = transactions.execute(status -> repository.claimReadyWorkflow().orElse(null));
        if (row == null) {
            return;
        }
        try {
            WorkflowStarter.WorkflowExecution execution = workflowStarter.start(
                    new WorkflowStarter.StartWorkflowCommand(row.workflowName(), row.workflowVersion(),
                            row.applicationId(), row.applicationId(), row.payload(), row.traceId()));
            transactions.executeWithoutResult(status -> repository.markWorkflowStarted(row, execution.workflowId()));
        } catch (Exception exception) {
            boolean retryableFailure = isRetryable(exception);
            boolean retryable = retryableFailure && row.attemptCount() < maxAttempts;
            String code = exception instanceof WorkflowStartException workflow
                    ? workflow.code() : "WORKFLOW_START_FAILED";
            transactions.executeWithoutResult(status -> repository.markWorkflowFailure(row, retryable, code,
                    retryable ? "Workflow start will be retried (" + code + ")"
                            : retryableFailure ? "Workflow start retry limit reached (" + code + ")"
                                    : "Workflow start was rejected (" + code + ")"));
        }
    }

    private static boolean isRetryable(Exception exception) {
        if (exception instanceof WorkflowStartException workflow) {
            return workflow.retryable();
        }
        if (exception instanceof ResourceAccessException || exception instanceof HttpServerErrorException) {
            return true;
        }
        return exception instanceof HttpClientErrorException.TooManyRequests;
    }
}
