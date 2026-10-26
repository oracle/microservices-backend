// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.gatewaybff;

import com.cloudbank.gatewaybff.MicroTxClient.Completion;
import com.cloudbank.gatewaybff.MicroTxClient.HumanInput;
import com.cloudbank.gatewaybff.MicroTxClient.HumanTaskSearch;
import com.cloudbank.gatewaybff.MicroTxClient.Notification;
import com.cloudbank.gatewaybff.MicroTxClient.Task;
import com.cloudbank.gatewaybff.MicroTxClient.Workflow;
import com.cloudbank.gatewaybff.MicroTxClient.WorkflowInput;
import java.util.Collections;
import java.util.List;
import jakarta.servlet.http.HttpServletRequest;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.client.ExpectedCount.manyTimes;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class ManualReviewControllerTest {
    private static final String ROOT = "/bff/api/v1/manual-review/tasks";
    private static final String PAYLOAD = """
            {"decisionOutcome":"APPROVED","reasonCode":"DOCUMENT_EXCEPTION_RESOLVED","policySection":"CBPL-150-S4"}
            """;
    private static final Completion COMPLETION = new Completion("APPROVED", "UNDERWRITER", "signed-reviewer",
            "DOCUMENT_EXCEPTION_RESOLVED", "CBPL-150-S4");
    private static final String LOAN = """
            {"applicationId":"APP-ONE","scenarioId":"SCN-ONE","scenarioName":"Synthetic manual review",
             "status":"MANUAL_REVIEW","workflow":{"workflowId":"wf-one","workflowName":"cloudbank-loan-origination",
              "workflowVersion":1},"restricted":"server-only-secret"}
            """;
    private SessionIdentity identity;
    private MicroTxClient microtx;
    private MockRestServiceServer loan;
    private MockMvc mvc;

    @BeforeEach
    void setup() {
        identity = mock(SessionIdentity.class);
        var user = new SessionIdentity.AuthorizedUser("obaas-admin", "server-held-user-token", null);
        when(identity.require(any(), any(HttpServletRequest.class))).thenReturn(user);
        when(identity.requireReviewer(any(), any(HttpServletRequest.class)))
                .thenReturn(new SessionIdentity.AuthorizedReviewer(user, "signed-reviewer"));
        microtx = mock(MicroTxClient.class);
        when(microtx.task(eq("task-one"), anyString())).thenReturn(task("IN_PROGRESS", null));
        when(microtx.workflow(eq("wf-one"), anyString())).thenReturn(workflow(1));
        var builder = RestClient.builder();
        loan = MockRestServiceServer.bindTo(builder).build();
        mvc = MockMvcBuilders.standaloneSetup(new ManualReviewController(identity, microtx,
                "http://loan.example", builder)).setControllerAdvice(new BffErrorHandler()).build();
    }

    @Test
    void listsOnlyVerifiedPendingCloudbankTasksAndReturnsSafeFields() throws Exception {
        loanAvailable();
        when(microtx.pending(anyInt(), anyInt(), anyString())).thenReturn(new HumanTaskSearch(2,
                List.of(notification("task-one", "cloudbank-loan-origination"), notification("other", "another-workflow"))));
        mvc.perform(get(ROOT)).andExpect(status().isOk())
                .andExpect(jsonPath("$.page.totalElements").value(1))
                .andExpect(jsonPath("$.content[0].taskId").value("task-one"))
                .andExpect(jsonPath("$.content[0].reasonLabel").value("Document evidence requires review"))
                .andExpect(jsonPath("$.content[0].inputData").doesNotExist())
                .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.header()
                        .string("Cache-Control", "no-store"))
                .andExpect(content().string(not(containsString("server-only-secret"))));
        verify(microtx, never()).task(eq("other"), anyString());
        loan.verify();
    }

    @Test
    void scansUpstreamPagesBeforeComputingAuthorizedPagination() throws Exception {
        loanAvailable();
        when(microtx.pending(eq(0), eq(100), anyString())).thenReturn(new HumanTaskSearch(101,
                Collections.nCopies(100, notification("other", "another-workflow"))));
        when(microtx.pending(eq(100), eq(100), anyString())).thenReturn(new HumanTaskSearch(101,
                List.of(notification("task-one", "cloudbank-loan-origination"))));
        mvc.perform(get(ROOT).param("size", "1")).andExpect(status().isOk())
                .andExpect(jsonPath("$.page.totalElements").value(1))
                .andExpect(jsonPath("$.page.totalPages").value(1));
        loan.verify();
    }

    @Test
    void hidesApplicationsOutsideTheSessionUsersAuthorizedScope() throws Exception {
        loan.expect(requestTo("http://loan.example/api/v1/loan-applications/APP-ONE"))
                .andRespond(withStatus(HttpStatus.FORBIDDEN).body("sensitive owner response"));
        when(microtx.pending(anyInt(), anyInt(), anyString())).thenReturn(new HumanTaskSearch(1,
                List.of(notification("task-one", "cloudbank-loan-origination"))));
        mvc.perform(get(ROOT)).andExpect(status().isOk()).andExpect(jsonPath("$.content").isEmpty());
        verify(microtx, never()).workflow(anyString(), anyString());
        loan.verify();
    }

    @Test
    void hidesWrongWorkflowVersionAndMismatchedLoanWorkflow() throws Exception {
        loanAvailable();
        when(microtx.workflow(eq("wf-one"), anyString())).thenReturn(workflow(2));
        mvc.perform(get(ROOT + "/task-one")).andExpect(status().isNotFound());
        verify(microtx, never()).complete(anyString(), any(), anyString(), anyString());
        loan.verify();
    }

    @Test
    void doesNotTrustNotificationTypeOrClientProvidedTaskId() throws Exception {
        var valid = task("IN_PROGRESS", null);
        when(microtx.task(eq("task-one"), anyString())).thenReturn(new Task(valid.taskId(), "HTTP",
                valid.referenceTaskName(), valid.status(), valid.workflowInstanceId(), valid.inputData(), null, 1, 1));
        mvc.perform(get(ROOT + "/task-one")).andExpect(status().isNotFound());
        verifyNoInteractionsWithLoan();
    }

    @Test
    void detailExposesTheTwoAllowedOutcomesAndScriptDefaults() throws Exception {
        loanAvailable();
        mvc.perform(get(ROOT + "/task-one")).andExpect(status().isOk())
                .andExpect(jsonPath("$.allowedDecisionOutcomes[0]").value("APPROVED"))
                .andExpect(jsonPath("$.allowedDecisionOutcomes[1]").value("REJECTED"))
                .andExpect(jsonPath("$.defaultReasonCode").value("DOCUMENT_EXCEPTION_RESOLVED"))
                .andExpect(jsonPath("$.defaultPolicySection").value("CBPL-150-S4"))
                .andExpect(jsonPath("$.reviewerRole").value("UNDERWRITER"))
                .andExpect(jsonPath("$.reviewer").value("obaas-admin"));
        loan.verify();
    }

    @ParameterizedTest
    @ValueSource(strings = {"APPROVED", "REJECTED"})
    void completesWithTheSignedReviewerAndLeavesTheFinalDecisionToTheWorkflow(String outcome) throws Exception {
        loanAvailable();
        mvc.perform(post(ROOT + "/task-one/resolution").header("Idempotency-Key", "resolution-one")
                .contentType(MediaType.APPLICATION_JSON).content(PAYLOAD.replace("APPROVED", outcome)))
                .andExpect(status().isAccepted()).andExpect(jsonPath("$.completionStatus").value("ACCEPTED"))
                .andExpect(jsonPath("$.decisionOutcome").value(outcome))
                .andExpect(jsonPath("$.correlationId").isNotEmpty());
        verify(microtx).complete(eq("wf-one"), eq(new Completion(outcome, "UNDERWRITER", "signed-reviewer",
                "DOCUMENT_EXCEPTION_RESOLVED", "CBPL-150-S4")), eq("resolution-one"), anyString());
        loan.verify();
    }

    @Test
    void repeatedIdenticalCompletionReconcilesDurableOutputWithoutAnotherPost() throws Exception {
        loanAvailable();
        when(microtx.task(eq("task-one"), anyString())).thenReturn(task("COMPLETED", COMPLETION));
        mvc.perform(post(ROOT + "/task-one/resolution").header("Idempotency-Key", "resolution-retry")
                .contentType(MediaType.APPLICATION_JSON).content(PAYLOAD)).andExpect(status().isAccepted());
        verify(microtx, never()).complete(anyString(), any(), anyString(), anyString());
        loan.verify();
    }

    @Test
    void reconcilesACompletionThatCommittedBeforeTheConnectionFailed() throws Exception {
        loanAvailable();
        when(microtx.task(eq("task-one"), anyString()))
                .thenReturn(task("IN_PROGRESS", null), task("COMPLETED", COMPLETION));
        doThrow(new ResourceAccessException("synthetic timeout with sensitive upstream text"))
                .when(microtx).complete(anyString(), any(), anyString(), anyString());
        mvc.perform(post(ROOT + "/task-one/resolution").header("Idempotency-Key", "resolution-retry")
                .contentType(MediaType.APPLICATION_JSON).content(PAYLOAD)).andExpect(status().isAccepted());
        loan.verify();
    }

    @Test
    void anUnreconciledTimeoutReturnsASafeRetryableError() throws Exception {
        loanAvailable();
        doThrow(new ResourceAccessException("sensitive upstream text"))
                .when(microtx).complete(anyString(), any(), anyString(), anyString());
        mvc.perform(post(ROOT + "/task-one/resolution").header("Idempotency-Key", "resolution-retry")
                .contentType(MediaType.APPLICATION_JSON).content(PAYLOAD))
                .andExpect(status().isServiceUnavailable()).andExpect(jsonPath("$.retryable").value(true))
                .andExpect(content().string(not(containsString("sensitive"))));
        loan.verify();
    }

    @Test
    void aDifferentAlreadyCommittedOutcomeIsAConflict() throws Exception {
        loanAvailable();
        when(microtx.task(eq("task-one"), anyString())).thenReturn(task("COMPLETED",
                new Completion("REJECTED", "UNDERWRITER", "signed-reviewer", "DOCUMENT_EXCEPTION_RESOLVED", "CBPL-150-S4")));
        mvc.perform(post(ROOT + "/task-one/resolution").header("Idempotency-Key", "resolution-retry")
                .contentType(MediaType.APPLICATION_JSON).content(PAYLOAD)).andExpect(status().isConflict());
        verify(microtx, never()).complete(anyString(), any(), anyString(), anyString());
        loan.verify();
    }

    @Test
    void reusingAnOperationKeyForAnotherPayloadIsAConflict() throws Exception {
        loanAvailable();
        var session = new MockHttpSession();
        mvc.perform(post(ROOT + "/task-one/resolution").session(session).header("Idempotency-Key", "resolution-one")
                .contentType(MediaType.APPLICATION_JSON).content(PAYLOAD)).andExpect(status().isAccepted());
        mvc.perform(post(ROOT + "/task-one/resolution").session(session).header("Idempotency-Key", "resolution-one")
                .contentType(MediaType.APPLICATION_JSON).content(PAYLOAD.replace("APPROVED", "REJECTED")))
                .andExpect(status().isConflict());
        verify(microtx, times(1)).complete(anyString(), any(), anyString(), anyString());
        loan.verify();
    }

    @ParameterizedTest
    @ValueSource(strings = {"{}", "{\"decisionOutcome\":\"MANUAL_REVIEW\"}",
            "{\"decisionOutcome\":\"APPROVED\",\"reasonCode\":\"bad reason\",\"policySection\":\"CBPL-150-S4\"}",
            "{\"decisionOutcome\":\"APPROVED\",\"reasonCode\":\"OKAY\",\"policySection\":\"invalid\"}"})
    void invalidCompletionFieldsNeverReachMicroTx(String payload) throws Exception {
        mvc.perform(post(ROOT + "/task-one/resolution").header("Idempotency-Key", "resolution-one")
                .contentType(MediaType.APPLICATION_JSON).content(payload)).andExpect(status().isBadRequest());
        verifyNoInteractions(microtx);
    }

    @ParameterizedTest
    @ValueSource(strings = {"reviewerPrincipalId", "reviewerRole", "workflowId", "outputData"})
    void browserCannotSupplyTechnicalOrAuditIdentityFields(String field) throws Exception {
        String payload = PAYLOAD.strip().replace("}", ",\"" + field + "\":\"untrusted\"}");
        mvc.perform(post(ROOT + "/task-one/resolution").header("Idempotency-Key", "resolution-one")
                .contentType(MediaType.APPLICATION_JSON).content(payload)).andExpect(status().isBadRequest());
        verifyNoInteractions(microtx);
    }

    @Test
    void completionRequiresAnUnderwriterEvenWhenTheUserCanReadTheQueue() throws Exception {
        when(identity.requireReviewer(any(), any())).thenThrow(new ResponseStatusException(HttpStatus.FORBIDDEN));
        mvc.perform(post(ROOT + "/task-one/resolution").header("Idempotency-Key", "resolution-one")
                .contentType(MediaType.APPLICATION_JSON).content(PAYLOAD)).andExpect(status().isForbidden());
        verifyNoInteractions(microtx);
    }

    @Test
    void refusesSilentlyTruncatedQueues() throws Exception {
        when(microtx.pending(anyInt(), anyInt(), anyString())).thenReturn(new HumanTaskSearch(1001, List.of()));
        mvc.perform(get(ROOT)).andExpect(status().isServiceUnavailable());
    }

    private void loanAvailable() {
        loan.expect(manyTimes(), requestTo("http://loan.example/api/v1/loan-applications/APP-ONE"))
                .andExpect(header("Authorization", "Bearer server-held-user-token"))
                .andExpect(header("X-Correlation-ID", org.hamcrest.Matchers.matchesPattern("[0-9a-f-]{36}")))
                .andRespond(withSuccess(LOAN, MediaType.APPLICATION_JSON));
    }

    private void verifyNoInteractionsWithLoan() { loan.verify(); }
    private static Notification notification(String id, String workflow) {
        return new Notification(id, "IN_PROGRESS", "human_task", "wf-one", workflow);
    }
    private static Task task(String status, Completion completion) {
        return new Task("task-one", "HUMAN", "human_task_manual_review", status, "wf-one",
                new HumanInput("APP-ONE", "DOCUMENT_REVIEW_REQUIRED", "DREV-ONE", "SUM-ONE", "ASSIST-ONE", "DEC-ONE"),
                completion, 1000, 2000);
    }
    private static Workflow workflow(int version) {
        return new Workflow("wf-one", "cloudbank-loan-origination", version, "RUNNING", new WorkflowInput("APP-ONE"));
    }
}
