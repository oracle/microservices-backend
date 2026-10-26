// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.documentingest.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.cloudbank.documentingest.client.LoanApplicationClient;
import com.cloudbank.documentingest.model.WorkflowExtractionModels.LoanDocument;
import com.cloudbank.documentingest.model.WorkflowExtractionModels.LoanDocumentManifest;
import com.cloudbank.documentingest.model.WorkflowExtractionModels.WorkflowExtractionRequest;
import com.cloudbank.documentingest.persistence.ExtractionRepository;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.web.server.ResponseStatusException;

class WorkflowExtractionServiceTest {

    private static final Path PACKET_ROOT = Path.of("..", "..", "synthetic_data", "customer_packets",
            "app_apr_001_elena_parker");

    @Test
    void reusesTheSameReadyPdfForTwoApplicationsUsingOnlyTheRuntimeContext() throws Exception {
        LoanApplicationClient client = mock(LoanApplicationClient.class);
        ExtractionRepository repository = mock(ExtractionRepository.class);
        var service = new WorkflowExtractionService(client,
                new DocumentIngestService(new PdfTextExtractor(), new DocumentParser()), repository);
        byte[] pdf = Files.readAllBytes(PACKET_ROOT.resolveSibling("demo_geocoded_loan").resolve("loan_application.pdf"));
        assertThat(new PdfTextExtractor().extractLines(pdf)).noneMatch(line -> line.contains("APP-"));
        when(repository.persist(anyString(), anyString(), anyString(), any(), anyString())).thenReturn("EXT-DEMO");
        for (String id : List.of("ONE", "TWO")) {
            String appId = "APP-" + id;
            LoanDocument document = document("DOC-" + id, "LOAN_APPLICATION", "loan_application.pdf", pdf);
            when(client.manifest(appId)).thenReturn(new LoanDocumentManifest(appId, List.of(document)));
            when(client.content(appId, document)).thenReturn(pdf);
            var response = service.extract(new WorkflowExtractionRequest(appId, "WF-" + id,
                    "extract_documents", "0123456789abcdef0123456789abcdef"), "demo-extract:" + id);
            assertThat(response.applicationId()).isEqualTo(appId);
            verify(repository).persist(eq(appId), eq("DOC-" + id), eq(document.contentSha256()),
                    argThat(extraction -> extraction.packets().getFirst().getApplicationId() == null
                            && extraction.packets().getFirst().getLoanRequest().getRequestedAmount() == 5000.0),
                    eq("0123456789abcdef0123456789abcdef"));
        }
    }

    @Test
    void rejectsAManifestForAnotherApplicationBeforeFetchingOrPersistingContent() {
        LoanApplicationClient client = mock(LoanApplicationClient.class);
        ExtractionRepository repository = mock(ExtractionRepository.class);
        var service = new WorkflowExtractionService(client,
                new DocumentIngestService(new PdfTextExtractor(), new DocumentParser()), repository);
        when(client.manifest("APP-ONE")).thenReturn(new LoanDocumentManifest("APP-OTHER", List.of()));
        assertThatThrownBy(() -> service.extract(new WorkflowExtractionRequest("APP-ONE", "WF-ONE",
                "extract_documents", "0123456789abcdef0123456789abcdef"), "demo-extract:ONE"))
                .isInstanceOfSatisfying(ResponseStatusException.class,
                        error -> assertThat(error.getStatusCode().value()).isEqualTo(502));
        verify(client, never()).content(anyString(), any());
        verify(repository, never()).persist(anyString(), anyString(), anyString(), any(), anyString());
    }

    @Test
    void retrievesVerifiesExtractsAndAcknowledgesSyntheticPdfs() throws Exception {
        LoanApplicationClient client = mock(LoanApplicationClient.class);
        ExtractionRepository repository = mock(ExtractionRepository.class);
        DocumentIngestService ingestService = new DocumentIngestService(new PdfTextExtractor(), new DocumentParser());
        WorkflowExtractionService service = new WorkflowExtractionService(
                client, ingestService, repository);

        byte[] loanPdf = Files.readAllBytes(PACKET_ROOT.resolve("loan_application.pdf"));
        byte[] payPdf = Files.readAllBytes(PACKET_ROOT.resolve("pay_statement_novereign_systems.pdf"));
        LoanDocument loan = document("DOC-LOAN", "LOAN_APPLICATION", "loan_application.pdf", loanPdf);
        LoanDocument pay = document("DOC-PAY", "PAY_STATEMENT", "pay_statement_novereign_systems.pdf", payPdf);
        when(client.manifest("APP-TEST"))
                .thenReturn(new LoanDocumentManifest("APP-TEST", List.of(loan, pay)));
        when(client.content("APP-TEST", loan)).thenReturn(loanPdf);
        when(client.content("APP-TEST", pay)).thenReturn(payPdf);
        when(repository.persist(anyString(), anyString(), anyString(), any(), anyString()))
                .thenAnswer(invocation -> "EXT-" + invocation.getArgument(1, String.class));

        var response = service.extract(new WorkflowExtractionRequest(
                "APP-TEST", "WF-TEST", "extract-documents", "0123456789abcdef0123456789abcdef"),
                "workflow-extract:APP-TEST");

        assertThat(response.results()).hasSize(2);
        assertThat(response.results()).allSatisfy(result -> {
            assertThat(result.extraction().packetCount()).isEqualTo(1);
            assertThat(result.extraction().packets().getFirst().getDocuments()).hasSize(1);
        });
        verify(client).transitionStatus("APP-TEST", loan,
                statusEventId("workflow-extract:APP-TEST", "DOC-LOAN", "EXTRACTED"),
                "EXTRACTED", "DOCUMENT_EXTRACTION_SUCCEEDED",
                "0123456789abcdef0123456789abcdef");
        verify(client).transitionStatus("APP-TEST", pay,
                statusEventId("workflow-extract:APP-TEST", "DOC-PAY", "EXTRACTED"),
                "EXTRACTED", "DOCUMENT_EXTRACTION_SUCCEEDED",
                "0123456789abcdef0123456789abcdef");
    }

    @Test
    void rejectsDigestMismatchAndMarksDocumentFailedFinal() throws Exception {
        LoanApplicationClient client = mock(LoanApplicationClient.class);
        ExtractionRepository repository = mock(ExtractionRepository.class);
        WorkflowExtractionService service = new WorkflowExtractionService(client,
                new DocumentIngestService(new PdfTextExtractor(), new DocumentParser()),
                repository);
        byte[] content = Files.readAllBytes(PACKET_ROOT.resolve("loan_application.pdf"));
        LoanDocument document = new LoanDocument("DOC-LOAN", "LOAN_APPLICATION", "loan_application.pdf",
                "RECEIVED", "application/pdf", (long) content.length, "0".repeat(64));
        when(client.manifest("APP-TEST"))
                .thenReturn(new LoanDocumentManifest("APP-TEST", List.of(document)));
        when(client.content("APP-TEST", document)).thenReturn(content);
        WorkflowExtractionRequest request = new WorkflowExtractionRequest(
                "APP-TEST", "WF-TEST", "extract-documents", "0123456789abcdef0123456789abcdef");

        assertThatThrownBy(() -> service.extract(request, "workflow-extract:APP-TEST"))
                .isInstanceOf(IllegalStateException.class)
                .hasMessage("Document SHA-256 verification failed");
        verify(client).transitionStatus("APP-TEST", document,
                statusEventId("workflow-extract:APP-TEST", "DOC-LOAN", "FAILED_FINAL"),
                "FAILED_FINAL", "DOCUMENT_INTEGRITY_CHECK_FAILED",
                "0123456789abcdef0123456789abcdef");
    }

    @Test
    void rejectsWorkflowExtractionWhenNoDocumentsAreProcessable() throws Exception {
        LoanApplicationClient client = mock(LoanApplicationClient.class);
        ExtractionRepository repository = mock(ExtractionRepository.class);
        WorkflowExtractionService service = new WorkflowExtractionService(client,
                new DocumentIngestService(new PdfTextExtractor(), new DocumentParser()),
                repository);
        LoanDocument expected = new LoanDocument("DOC-LOAN", "LOAN_APPLICATION", "loan_application.pdf",
                "EXPECTED", "application/pdf", null, null);
        when(client.manifest("APP-TEST"))
                .thenReturn(new LoanDocumentManifest("APP-TEST", List.of(expected)));
        WorkflowExtractionRequest request = new WorkflowExtractionRequest(
                "APP-TEST", "WF-TEST", "extract-documents", "0123456789abcdef0123456789abcdef");

        assertThatThrownBy(() -> service.extract(request, "workflow-extract:APP-TEST"))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("No processable documents were found for the application");
    }

    private static LoanDocument document(String id, String type, String fileName, byte[] content) throws Exception {
        return new LoanDocument(id, type, fileName, "RECEIVED", "application/pdf",
                (long) content.length, sha256(content));
    }

    private static String statusEventId(String idempotencyKey, String documentId, String targetStatus)
            throws Exception {
        return "EXTSTAT-" + sha256((idempotencyKey + ":" + documentId + ":" + targetStatus).getBytes());
    }

    private static String sha256(byte[] content) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(content));
    }
}
