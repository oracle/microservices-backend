// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.documentingest.service;

import com.cloudbank.documentingest.client.LoanApplicationClient;
import com.cloudbank.documentingest.model.ExtractionModels.ExtractionResponse;
import com.cloudbank.documentingest.model.WorkflowExtractionModels.DocumentExtractionResult;
import com.cloudbank.documentingest.model.WorkflowExtractionModels.LoanDocument;
import com.cloudbank.documentingest.model.WorkflowExtractionModels.LoanDocumentManifest;
import com.cloudbank.documentingest.model.WorkflowExtractionModels.WorkflowExtractionRequest;
import com.cloudbank.documentingest.model.WorkflowExtractionModels.WorkflowExtractionResponse;
import com.cloudbank.documentingest.persistence.ExtractionRepository;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

@Service
public class WorkflowExtractionService {

    private final LoanApplicationClient loanClient;
    private final DocumentIngestService ingestService;
    private final ExtractionRepository repository;

    public WorkflowExtractionService(LoanApplicationClient loanClient, DocumentIngestService ingestService,
            ExtractionRepository repository) {
        this.loanClient = loanClient;
        this.ingestService = ingestService;
        this.repository = repository;
    }

    public WorkflowExtractionResponse extract(WorkflowExtractionRequest request, String idempotencyKey)
            throws java.io.IOException {
        LoanDocumentManifest manifest = loanClient.manifest(request.applicationId());
        if (manifest != null && !request.applicationId().equals(manifest.applicationId())) {
            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Document manifest application context mismatch");
        }
        if (manifest == null || manifest.documents() == null || manifest.documents().isEmpty()) {
            throw noProcessableDocuments();
        }
        List<LoanDocument> processableDocuments = manifest
                .documents().stream().filter(document -> "RECEIVED".equals(document.status())
                        || "FAILED_RETRYABLE".equals(document.status()) || "EXTRACTED".equals(document.status()))
                .toList();
        if (processableDocuments.isEmpty()) {
            throw noProcessableDocuments();
        }
        List<DocumentExtractionResult> results = new ArrayList<>();
        for (LoanDocument document : processableDocuments) {
            try {
                byte[] content = loanClient.content(request.applicationId(), document);
                verify(document, content);
                ExtractionResponse extraction = ingestService.extractPdf(document.fileName(), content);
                String extractionId = repository.persist(request.applicationId(), document.documentId(),
                        document.contentSha256(), extraction, request.traceId());
                if (!"EXTRACTED".equals(document.status())) {
                    loanClient.transitionStatus(request.applicationId(), document,
                            statusEventId(idempotencyKey, document.documentId(), "EXTRACTED"), "EXTRACTED",
                            "DOCUMENT_EXTRACTION_SUCCEEDED", request.traceId());
                }
                results.add(new DocumentExtractionResult(document.documentId(), extractionId, extraction));
            } catch (DocumentIntegrityException exception) {
                acknowledgeFailure(request, idempotencyKey, document, "FAILED_FINAL", "DOCUMENT_INTEGRITY_CHECK_FAILED",
                        exception);
                throw exception;
            } catch (java.io.IOException | RuntimeException exception) {
                acknowledgeFailure(request, idempotencyKey, document, "FAILED_RETRYABLE",
                        "DOCUMENT_EXTRACTION_FAILED_RETRYABLE", exception);
                throw exception;
            }
        }
        return new WorkflowExtractionResponse(request.applicationId(), request.workflowId(), request.taskReference(),
                List.copyOf(results));
    }

    private static void verify(LoanDocument document, byte[] content) {
        if (content == null || document.contentLengthBytes() == null
                || content.length != document.contentLengthBytes()) {
            throw new DocumentIntegrityException("Document length verification failed");
        }
        if (!sha256(content).equalsIgnoreCase(document.contentSha256())) {
            throw new DocumentIntegrityException("Document SHA-256 verification failed");
        }
    }

    private static ResponseStatusException noProcessableDocuments() {
        return new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "No processable documents were found for the application");
    }

    private static String sha256(byte[] content) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(content));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }

    private void acknowledgeFailure(WorkflowExtractionRequest request, String idempotencyKey, LoanDocument document,
            String targetStatus, String reasonCode, Exception failure) {
        if ("EXTRACTED".equals(document.status())) {
            return;
        }
        try {
            loanClient.transitionStatus(request.applicationId(), document,
                    statusEventId(idempotencyKey, document.documentId(), targetStatus), targetStatus, reasonCode,
                    request.traceId());
        } catch (RuntimeException callbackFailure) {
            failure.addSuppressed(callbackFailure);
        }
    }

    private static String statusEventId(String idempotencyKey, String documentId, String targetStatus) {
        String source = idempotencyKey + ":" + documentId + ":" + targetStatus;
        return "EXTSTAT-" + sha256(source.getBytes(StandardCharsets.UTF_8));
    }

    private static final class DocumentIntegrityException extends IllegalStateException {

        private DocumentIntegrityException(String message) {
            super(message);
        }
    }
}
