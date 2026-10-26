// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.service;

import static com.cloudbank.loanapplication.api.ApplicationApiModels.ApplicantRequest;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.AddressRequest;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.CreateApplicationRequest;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.DocumentRequest;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.DocumentStatusTransitionRequest;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.LoanRequest;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.cloudbank.loanapplication.api.ApplicationApiModels.ApplicationPageResponse;
import com.cloudbank.loanapplication.domain.ApplicationStatus;
import com.cloudbank.loanapplication.domain.DocumentStatus;
import com.cloudbank.loanapplication.domain.WorkflowDispatchStatus;
import com.cloudbank.loanapplication.domain.WorkflowStartMode;
import com.cloudbank.loanapplication.persistence.LoanApplicationRepository;
import com.cloudbank.loanapplication.persistence.PrincipalProjection;
import com.cloudbank.loanapplication.persistence.LoanRecords.ApplicationRow;
import com.cloudbank.loanapplication.persistence.LoanRecords.DocumentContentRow;
import com.cloudbank.loanapplication.persistence.LoanRecords.DocumentProcessingRow;
import com.cloudbank.loanapplication.persistence.LoanRecords.WorkflowRow;
import com.cloudbank.loanapplication.security.AuthenticatedPrincipal;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import org.mockito.ArgumentCaptor;

class LoanApplicationServiceTest {

    private LoanApplicationRepository repository;
    private LoanApplicationService service;

    @BeforeEach
    void setUp() {
        repository = mock(LoanApplicationRepository.class);
        PrincipalProjection principals = mock(PrincipalProjection.class);
        service = new LoanApplicationService(repository, principals, new ObjectMapper(),
                "cloudbank-loan-origination");
        when(repository.findByApplicationId("APP-test")).thenReturn(Optional.of(applicationRow()));
        when(repository.hasApplicationAccess(20L, "principal-1")).thenReturn(true);
    }

    @Test
    void schedulesAutoWorkflowWhenRequiredDocumentIsExpected() throws Exception {
        CreateApplicationRequest request = request(DocumentStatus.EXPECTED, WorkflowStartMode.AUTO);
        AuthenticatedPrincipal principal = principal();
        when(repository.findByIdempotency("principal-1", "idem-key-123")).thenReturn(Optional.empty());
        when(repository.insertApplicant(any(), any())).thenReturn(10L);
        when(repository.insertApplication(any(), any(Long.class), any(), any(), any(), any())).thenReturn(20L);
        ApplicationRow row = applicationRow();
        when(repository.findByApplicationId(any())).thenReturn(Optional.of(row));
        when(repository.findDocuments(20L)).thenReturn(List.of());
        when(repository.findWorkflow(20L)).thenReturn(Optional.of(new WorkflowRow(30L, 20L, "APP-test", "WFR-test",
                "cloudbank-loan-origination", 1, WorkflowDispatchStatus.WAITING_FOR_DOCUMENTS, "{}", 0,
                "0123456789abcdef0123456789abcdef", null, null, null)));

        service.create(request, "idem-key-123", principal);

        verify(repository).insertAddress(any(Long.class), anyString(), any());
        ArgumentCaptor<WorkflowDispatchStatus> status = ArgumentCaptor.forClass(WorkflowDispatchStatus.class);
        ArgumentCaptor<Integer> workflowVersion = ArgumentCaptor.forClass(Integer.class);
        ArgumentCaptor<String> payload = ArgumentCaptor.forClass(String.class);
        verify(repository).insertWorkflowStart(any(Long.class), any(), any(), workflowVersion.capture(), any(),
                status.capture(), payload.capture(), any());
        assertThat(workflowVersion.getValue()).isEqualTo(1);
        assertThat(status.getValue()).isEqualTo(WorkflowDispatchStatus.WAITING_FOR_DOCUMENTS);
        JsonNode workflowInput = new ObjectMapper().readTree(payload.getValue());
        assertThat(workflowInput.path("applicationId").asText()).startsWith("APP-");
        assertThat(workflowInput.path("traceId").asText()).hasSize(32);
        assertThat(workflowInput.path("scenarioId").asText()).isEqualTo("scenario");
        assertThat(workflowInput.path("scenarioName").asText()).isEqualTo("Scenario");
        assertThat(workflowInput.path("documentCount").asInt()).isEqualTo(1);
    }

    @Test
    void returnsStablePageMetadataForPopulatedResults() {
        ApplicationRow row = applicationRow();
        when(repository.findApplications(null, "scenario", "principal-1", 40, 20)).thenReturn(List.of(row));
        when(repository.countApplications(null, "scenario", "principal-1")).thenReturn(42L);
        when(repository.findDocuments(20L)).thenReturn(List.of());
        when(repository.findWorkflow(20L)).thenReturn(Optional.empty());

        ApplicationPageResponse result = service.list(null, "scenario", 2, 20, principal());

        assertThat(result.content()).hasSize(1);
        assertThat(result.page().number()).isEqualTo(2);
        assertThat(result.page().size()).isEqualTo(20);
        assertThat(result.page().totalElements()).isEqualTo(42);
        assertThat(result.page().totalPages()).isEqualTo(3);
    }

    @Test
    void returnsZeroPagesForAnEmptyResult() {
        when(repository.findApplications(null, null, "principal-1", 0, 20)).thenReturn(List.of());
        when(repository.countApplications(null, null, "principal-1")).thenReturn(0L);

        ApplicationPageResponse result = service.list(null, null, 0, 20, principal());

        assertThat(result.content()).isEmpty();
        assertThat(result.page().number()).isZero();
        assertThat(result.page().size()).isEqualTo(20);
        assertThat(result.page().totalElements()).isZero();
        assertThat(result.page().totalPages()).isZero();
    }

    @Test
    void preservesRequestedPageBeyondTheLastPage() {
        when(repository.findApplications(null, null, "principal-1", 100, 20)).thenReturn(List.of());
        when(repository.countApplications(null, null, "principal-1")).thenReturn(42L);

        ApplicationPageResponse result = service.list(null, null, 5, 20, principal());

        assertThat(result.content()).isEmpty();
        assertThat(result.page().number()).isEqualTo(5);
        assertThat(result.page().totalElements()).isEqualTo(42);
        assertThat(result.page().totalPages()).isEqualTo(3);
    }

    @Test
    void storesExpectedPdfAndMarksDocumentReceived() {
        byte[] content = "%PDF synthetic".getBytes();
        DocumentProcessingRow document = processingDocument(DocumentStatus.EXPECTED);
        when(repository.findProcessingDocument("APP-test", "DOC-test")).thenReturn(Optional.of(document));
        when(repository.findDocumentContent(30L)).thenReturn(Optional.empty());
        when(repository.markDocumentReceived(anyLong(), anyString(), anyString(), anyLong(), anyString()))
                .thenReturn(1);

        var response = service.uploadDocumentContent("APP-test", "DOC-test", "upload-key-123", "application/pdf",
                content, principal());

        assertThat(response.status()).isEqualTo(DocumentStatus.RECEIVED);
        assertThat(response.contentLengthBytes()).isEqualTo(content.length);
        assertThat(response.contentSha256()).hasSize(64);
        verify(repository).insertDocumentContent(document, response.contentSha256(), content.length, "application/pdf",
                "upload-key-123", content);
        verify(repository).promoteWaitingWorkflow(20L);
    }

    @Test
    void rejectsDifferentBytesAfterContentIsStored() {
        DocumentProcessingRow document = processingDocument(DocumentStatus.RECEIVED);
        when(repository.findProcessingDocument("APP-test", "DOC-test")).thenReturn(Optional.of(document));
        when(repository.findDocumentContent(30L)).thenReturn(Optional
                .of(new DocumentContentRow("0".repeat(64), 10, "application/pdf", "upload-key-123", new byte[10])));

        assertThatThrownBy(() -> service.uploadDocumentContent("APP-test", "DOC-test", "upload-key-123",
                "application/pdf", "%PDF changed".getBytes(), principal())).isInstanceOfSatisfying(
                        LoanServiceException.class,
                        exception -> assertThat(exception.code()).isEqualTo("DOCUMENT_CONTENT_CONFLICT"));
    }

    @Test
    void explicitlyReleasesDeferredProcessingThroughTheExistingOutbox() {
        when(repository.releaseDeferred(20L)).thenReturn(1);
        when(repository.findDocuments(20L)).thenReturn(List.of());
        when(repository.findWorkflow(20L)).thenReturn(Optional.of(workflow(WorkflowDispatchStatus.PENDING)));
        var result = service.releaseWorkflow("APP-test", principal());
        assertThat(result.workflow().dispatchStatus()).isEqualTo(WorkflowDispatchStatus.PENDING);
        verify(repository).releaseDeferred(20L);
    }

    @ParameterizedTest
    @EnumSource(value = WorkflowDispatchStatus.class, names = {"PENDING", "IN_PROGRESS", "FAILED_RETRYABLE", "STARTED"})
    void reconcilesRepeatedReleaseWhileTheOutboxIsDispatchingOrRetrying(WorkflowDispatchStatus status) {
        when(repository.releaseDeferred(20L)).thenReturn(0);
        when(repository.findDocuments(20L)).thenReturn(List.of());
        when(repository.findWorkflow(20L)).thenReturn(Optional.of(workflow(status)));
        assertThat(service.releaseWorkflow("APP-test", principal()).workflow().dispatchStatus()).isEqualTo(status);
    }

    @ParameterizedTest
    @EnumSource(value = WorkflowDispatchStatus.class, names = {"DEFERRED", "WAITING_FOR_DOCUMENTS", "FAILED_FINAL", "CANCELLED"})
    void rejectsReleaseWhenTheOutboxDidNotAcceptIt(WorkflowDispatchStatus status) {
        when(repository.releaseDeferred(20L)).thenReturn(0);
        when(repository.findWorkflow(20L)).thenReturn(Optional.of(workflow(status)));
        assertThatThrownBy(() -> service.releaseWorkflow("APP-test", principal()))
                .isInstanceOfSatisfying(LoanServiceException.class,
                        error -> assertThat(error.code()).isEqualTo("WORKFLOW_NOT_RELEASABLE"));
    }

    private static WorkflowRow workflow(WorkflowDispatchStatus status) {
        return new WorkflowRow(1L, 20L, "APP-test", "WFR-test", "cloudbank-loan-origination", 1,
                status, "{}", 1, "synthetic-trace", null, null, null);
    }

    @Test
    void acceptsDocumentReviewTransitionFromExtractedToValidated() {
        DocumentProcessingRow document = processingDocument(DocumentStatus.EXTRACTED);
        when(repository.findProcessingDocument("APP-test", "DOC-test")).thenReturn(Optional.of(document));
        when(repository.updateDocumentStatus(30L, DocumentStatus.EXTRACTED, DocumentStatus.VALIDATED)).thenReturn(1);
        when(repository.findDocumentContent(30L)).thenReturn(Optional
                .of(new DocumentContentRow("0".repeat(64), 10, "application/pdf", "upload-key-123", new byte[10])));

        var response = service.transitionDocument("APP-test", "DOC-test",
                new DocumentStatusTransitionRequest("event-123", DocumentStatus.EXTRACTED, DocumentStatus.VALIDATED,
                        "DOCUMENT_REVIEW_VALIDATED", "trace-123"),
                principal());

        assertThat(response.status()).isEqualTo(DocumentStatus.VALIDATED);
        verify(repository).updateDocumentStatus(30L, DocumentStatus.EXTRACTED, DocumentStatus.VALIDATED);
    }

    private static ApplicationRow applicationRow() {
        return new ApplicationRow(20L, "APP-test", "scenario", "Scenario", ApplicationStatus.SUBMITTED,
                new BigDecimal("5000.00"), 24, "DEBT_CONSOLIDATION", "hash", Instant.now(), Instant.now());
    }

    private static CreateApplicationRequest request(DocumentStatus status, WorkflowStartMode mode) {
        return new CreateApplicationRequest("scenario", "Scenario",
                new ApplicantRequest("Synthetic Applicant", "phone-token", "email-token", "25-34",
                        new AddressRequest("6 East Orison Crossing", "East Orison", "CX", "address-token")),
                new LoanRequest(new BigDecimal("5000.00"), 24, "DEBT_CONSOLIDATION", "2026.0"),
                List.of(new DocumentRequest("LOAN_APPLICATION", "application.pdf", status, true,
                        status == DocumentStatus.RECEIVED ? "a".repeat(64) : null,
                        status == DocumentStatus.RECEIVED ? "object/application.pdf" : null, "application/pdf", 100L)),
                mode);
    }

    private static DocumentProcessingRow processingDocument(DocumentStatus status) {
        return new DocumentProcessingRow(30L, 20L, "APP-test", "DOC-test", "LOAN_APPLICATION", "application.pdf",
                status, status == DocumentStatus.EXPECTED ? null : "application/pdf",
                status == DocumentStatus.EXPECTED ? null : 10L,
                status == DocumentStatus.EXPECTED ? null : "0".repeat(64), true);
    }

    private static AuthenticatedPrincipal principal() {
        return new AuthenticatedPrincipal("principal-1", "https://auth", "applicant-1", "Applicant One", null, "user",
                List.of("ROLE_APPLICANT"));
    }
}
