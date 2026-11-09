// Copyright (c) 2026, Oracle and/or its affiliates.
package com.cloudbank.loanapplication.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.cloudbank.loanapplication.api.ApplicationApiModels.WorkspaceDocument;
import com.cloudbank.loanapplication.domain.ApplicationStatus;
import com.cloudbank.loanapplication.domain.DocumentStatus;
import com.cloudbank.loanapplication.persistence.LoanApplicationRepository;
import com.cloudbank.loanapplication.persistence.LoanRecords.ApplicationRow;
import com.cloudbank.loanapplication.persistence.LoanRecords.DocumentContentRow;
import com.cloudbank.loanapplication.persistence.LoanRecords.DocumentProcessingRow;
import com.cloudbank.loanapplication.persistence.PrincipalProjection;
import com.cloudbank.loanapplication.security.AuthenticatedPrincipal;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.stream.IntStream;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class LoanWorkspaceTest {
    private LoanApplicationRepository repository;
    private LoanApplicationService service;
    private final AuthenticatedPrincipal user = new AuthenticatedPrincipal("user-1", "https://issuer", "user", "User",
            null, "user", List.of("ROLE_APPLICANT"));

    @BeforeEach
    void setup() {
        repository = mock(LoanApplicationRepository.class);
        service = new LoanApplicationService(repository, mock(PrincipalProjection.class), new ObjectMapper(),
                "cloudbank-loan-origination");
        when(repository.findByApplicationId("APP-test")).thenReturn(Optional.of(new ApplicationRow(1L, "APP-test",
                "SCN-test", "Synthetic application", ApplicationStatus.PROCESSING, new BigDecimal("5000"), 24,
                "OTHER_CONSUMER_PURPOSE", "hash", Instant.now(), Instant.now())));
        when(repository.hasApplicationAccess(1L, "user-1")).thenReturn(true);
    }

    @Test
    void boundsInventoryWithoutReadingAnyPdfOrRunningBusinessWrites() {
        when(repository.findWorkspaceDocuments(1L)).thenReturn(IntStream.range(0, 101).mapToObj(i ->
                new WorkspaceDocument("DOC-" + i, "LOAN_APPLICATION", null, "loan.pdf", DocumentStatus.VALIDATED,
                        true, false, null, null, null)).toList());
        when(repository.findOverview(1L)).thenReturn(Optional.empty());
        when(repository.findWorkflow(1L)).thenReturn(Optional.empty());
        var result = service.workspace("APP-test", user);
        assertThat(result.documents()).hasSize(100);
        assertThat(result.documentsTruncated()).isTrue();
        assertThat(result.documents()).allMatch(d -> !d.contentAvailable());
        verify(repository, never()).findDocumentPreviewContent(anyLong());
        verify(repository, never()).releaseDeferred(anyLong());
    }

    @Test
    void deniesApplicationAccessBeforeReadingApplicantOrDocumentData() {
        when(repository.hasApplicationAccess(1L, "user-1")).thenReturn(false);
        assertThatThrownBy(() -> service.workspace("APP-test", user)).isInstanceOf(LoanServiceException.class);
        assertThatThrownBy(() -> service.previewDocument("APP-test", "DOC-test", user)).isInstanceOf(LoanServiceException.class);
        verify(repository, never()).findOverview(anyLong());
        verify(repository, never()).findWorkspaceDocuments(anyLong());
        verify(repository, never()).findDocumentPreviewContent(anyLong());
    }

    @Test
    void rejectsDocumentFromAnotherApplicationBeforeReadingContent() {
        when(repository.findProcessingDocument("APP-test", "DOC-other")).thenReturn(Optional.empty());
        assertThatThrownBy(() -> service.previewDocument("APP-test", "DOC-other", user))
                .isInstanceOfSatisfying(LoanServiceException.class, e -> assertThat(e.status().value()).isEqualTo(404));
        verify(repository, never()).findDocumentPreviewContent(anyLong());
    }

    @Test
    void returnsStoredPdfForAuthorizedUserAndHandlesMissingOrCorruptContent() {
        when(repository.findProcessingDocument("APP-test", "DOC-test")).thenReturn(Optional.of(
                new DocumentProcessingRow(2L, 1L, "APP-test", "DOC-test", "LOAN_APPLICATION", "loan.pdf",
                        DocumentStatus.VALIDATED, "application/pdf", 4L, "a".repeat(64), true)));
        when(repository.findDocumentPreviewContent(2L)).thenReturn(Optional.of(
                new DocumentContentRow("a".repeat(64), 4L, "application/pdf", "key", new byte[]{1, 2, 3, 4})));
        assertThat(service.previewDocument("APP-test", "DOC-test", user).content()).containsExactly(1, 2, 3, 4);
        when(repository.findDocumentPreviewContent(2L)).thenReturn(Optional.empty());
        assertThatThrownBy(() -> service.previewDocument("APP-test", "DOC-test", user)).isInstanceOf(LoanServiceException.class);
        when(repository.findDocumentPreviewContent(2L)).thenReturn(Optional.of(
                new DocumentContentRow("a".repeat(64), 4L, "text/html", "key", new byte[4])));
        assertThatThrownBy(() -> service.previewDocument("APP-test", "DOC-test", user))
                .isInstanceOfSatisfying(LoanServiceException.class, e -> assertThat(e.status().value()).isEqualTo(503));
    }

    @Test
    void serviceTokensCannotUseTheUserPreviewBoundary() {
        var worker = new AuthenticatedPrincipal("worker", "https://issuer", "worker", "Worker", "ingest", "service", List.of("ROLE_SERVICE"));
        assertThatThrownBy(() -> service.workspace("APP-test", worker)).isInstanceOf(LoanServiceException.class);
        assertThatThrownBy(() -> service.previewDocument("APP-test", "DOC-test", worker)).isInstanceOf(LoanServiceException.class);
        verify(repository, never()).findByApplicationId(anyString());
    }
}
