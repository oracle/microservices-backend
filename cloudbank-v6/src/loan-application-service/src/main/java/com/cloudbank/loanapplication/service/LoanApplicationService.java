// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.service;

import static com.cloudbank.loanapplication.api.ApplicationApiModels.ApplicationResponse;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.ApplicationPageResponse;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.CreateApplicationRequest;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.DocumentRequest;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.DocumentManifestResponse;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.DocumentResponse;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.DocumentStatusTransitionRequest;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.DocumentUploadResponse;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.PageMetadata;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.ProcessingDocument;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.RegisterDocumentsRequest;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.StatusTransitionRequest;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.WorkflowResponse;
import static com.cloudbank.loanapplication.persistence.LoanRecords.ApplicationRow;

import com.cloudbank.loanapplication.domain.ApplicationStatus;
import com.cloudbank.loanapplication.domain.DocumentStatus;
import com.cloudbank.loanapplication.domain.WorkflowDispatchStatus;
import com.cloudbank.loanapplication.domain.WorkflowStartMode;
import com.cloudbank.loanapplication.persistence.LoanApplicationRepository;
import com.cloudbank.loanapplication.persistence.PrincipalProjection;
import com.cloudbank.loanapplication.persistence.LoanRecords.WorkflowRow;
import com.cloudbank.loanapplication.persistence.LoanRecords.DocumentProcessingRow;
import com.cloudbank.loanapplication.security.AuthenticatedPrincipal;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.MapperFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

@Service
public class LoanApplicationService {

    private static final Set<Integer> TERMS = Set.of(24, 36, 48, 60);
    private static final Set<String> PURPOSES = Set.of("DEBT_CONSOLIDATION", "HOME_IMPROVEMENT", "MAJOR_PURCHASE",
            "MEDICAL_EXPENSE", "HOUSEHOLD_EXPENSE", "MOVING_EXPENSE", "OTHER_CONSUMER_PURPOSE");
    private static final Set<String> DOCUMENT_TYPES = Set.of("LOAN_APPLICATION", "DISCLOSURE_CONSENT",
            "IDENTITY_SUMMARY", "ADDRESS_VERIFICATION", "INCOME_VALIDATION", "PAY_STATEMENT", "DEPOSIT_SUMMARY",
            "ACCOUNT_ACTIVITY", "CONTRACTOR_INCOME", "LIABILITY_SCHEDULE", "PAYMENT_CALCULATION",
            "CLARIFICATION_REQUEST", "DOCUMENT_RECEIPT", "RELATIONSHIP_SIGNAL");
    private static final int MAX_DOCUMENT_BYTES = 25 * 1024 * 1024;
    private static final int WORKFLOW_VERSION = 1;

    private final LoanApplicationRepository repository;
    private final PrincipalProjection principals;
    private final ObjectMapper canonicalMapper;
    private final String workflowName;

    public LoanApplicationService(LoanApplicationRepository repository, PrincipalProjection principals,
            ObjectMapper objectMapper,
            @Value("${cloudbank.workflow.name:cloudbank-loan-origination}") String workflowName) {
        this.repository = repository;
        this.principals = principals;
        this.canonicalMapper = objectMapper.copy().configure(MapperFeature.SORT_PROPERTIES_ALPHABETICALLY, true)
                .configure(SerializationFeature.ORDER_MAP_ENTRIES_BY_KEYS, true);
        this.workflowName = workflowName;
    }

    @Transactional
    public ApplicationResponse create(CreateApplicationRequest request, String idempotencyKey,
            AuthenticatedPrincipal principal) {
        validatePrincipalCanCreate(principal);
        validateRequest(request);
        String requestHash = hash(request);
        principals.requireIdentity(principal);
        if (principal.hasRole("ROLE_APPLICANT")) {
            principals.ensureApplicantPrincipal(principal);
        }
        var existing = repository.findByIdempotency(principal.principalId(), idempotencyKey);
        if (existing.isPresent()) {
            if (!requestHash.equalsIgnoreCase(existing.get().requestHash())) {
                throw new LoanServiceException("IDEMPOTENCY_CONFLICT", HttpStatus.CONFLICT,
                        "The idempotency key was already used for a different request");
            }
            return response(existing.get());
        }

        String applicantId = externalId("CUS-");
        String applicationId = externalId("APP-");
        String startRequestId = externalId("WFR-");
        String traceId = traceId();
        long applicantSk = repository.insertApplicant(applicantId, request);
        repository.insertAddress(applicantSk, compactExternalId("ADDR-"), request);
        long applicationSk = repository.insertApplication(applicationId, applicantSk, request, principal,
                idempotencyKey, requestHash);
        repository.grantOwner(applicationId, principal.principalId());
        request.documents()
                .forEach(document -> repository.insertDocument(applicationSk, externalId("DOC-"), document));

        WorkflowDispatchStatus dispatchStatus = initialDispatchStatus(request);
        repository.insertWorkflowStart(applicationSk, startRequestId, workflowName, WORKFLOW_VERSION,
                request.workflowStartMode().name(), dispatchStatus,
                workflowPayload(applicationId, request, traceId), traceId);
        repository.insertAudit(applicationSk, externalId("AUD-"), principal.principalId(), "INTAKE_CREATED",
                "SUCCESS", "LOAN_APPLICATION", applicationId, traceId);
        repository.insertTelemetry(applicationSk, externalId("TEL-"), traceId);
        return response(repository.findByApplicationId(applicationId).orElseThrow());
    }

    @Transactional(readOnly = true)
    public ApplicationResponse get(String applicationId, AuthenticatedPrincipal principal) {
        principals.requireIdentity(principal);
        return response(authorizedApplication(applicationId, principal));
    }

    @Transactional(readOnly = true)
    public ApplicationPageResponse list(ApplicationStatus status, String scenarioId, int page, int size,
            AuthenticatedPrincipal principal) {
        int safePage = Math.max(0, page);
        int safeSize = Math.min(100, Math.max(1, size));
        principals.requireIdentity(principal);
        List<ApplicationResponse> content = repository
                .findApplications(status, scenarioId, principal.principalId(), safePage * safeSize, safeSize)
                .stream().map(this::response).toList();
        long total = repository.countApplications(status, scenarioId, principal.principalId());
        long totalPages = total == 0 ? 0 : 1 + ((total - 1) / safeSize);
        return new ApplicationPageResponse(content, new PageMetadata(safePage, safeSize, total, totalPages));
    }

    @Transactional
    public ApplicationResponse registerDocuments(String applicationId, RegisterDocumentsRequest request,
            String idempotencyKey, AuthenticatedPrincipal principal) {
        request.documents().forEach(this::validateDocument);
        String requestHash = hash(request);
        principals.requireIdentity(principal);
        ApplicationRow application = authorizedApplication(applicationId, principal);
        Optional<String> existingHash = repository.findDocumentRegistrationHash(application.applicationSk(),
                principal.principalId(), idempotencyKey);
        if (existingHash.isPresent()) {
            if (!requestHash.equalsIgnoreCase(existingHash.get())) {
                throw new LoanServiceException("IDEMPOTENCY_CONFLICT", HttpStatus.CONFLICT,
                        "The idempotency key was already used for different document metadata");
            }
            return response(application);
        }
        request.documents().forEach(
                document -> repository.insertDocument(application.applicationSk(), externalId("DOC-"), document));
        repository.insertDocumentRegistration(application.applicationSk(), principal.principalId(), idempotencyKey,
                requestHash);
        repository.promoteWaitingWorkflow(application.applicationSk());
        WorkflowRow workflow = repository.findWorkflow(application.applicationSk()).orElseThrow();
        repository.insertAudit(application.applicationSk(), externalId("AUD-"), principal.principalId(),
                "DOCUMENT_METADATA_REGISTERED", "SUCCESS", "LOAN_APPLICATION", applicationId, workflow.traceId());
        return response(repository.findByApplicationId(applicationId).orElseThrow());
    }

    @Transactional
    public DocumentUploadResponse uploadDocumentContent(String applicationId, String documentId, String idempotencyKey,
            String mediaType, byte[] content, AuthenticatedPrincipal principal) {
        validatePrincipalCanCreate(principal);
        if (!"application/pdf".equalsIgnoreCase(mediaType)) {
            throw new LoanServiceException("UNSUPPORTED_DOCUMENT_MEDIA_TYPE", HttpStatus.UNSUPPORTED_MEDIA_TYPE,
                    "Workflow-managed document content must be a PDF");
        }
        if (content == null || content.length == 0 || content.length > MAX_DOCUMENT_BYTES) {
            throw new LoanServiceException("DOCUMENT_SIZE_INVALID", HttpStatus.CONTENT_TOO_LARGE,
                    "Document content must contain 1 to 26214400 bytes");
        }
        String contentSha256 = hashBytes(content);
        principals.requireIdentity(principal);
        authorizedApplication(applicationId, principal);
        DocumentProcessingRow document = repository.findProcessingDocument(applicationId, documentId)
                .orElseThrow(this::notFound);
        var existing = repository.findDocumentContent(document.documentSk());
        if (existing.isPresent()) {
            if (!contentSha256.equalsIgnoreCase(existing.get().contentSha256())) {
                throw new LoanServiceException("DOCUMENT_CONTENT_CONFLICT", HttpStatus.CONFLICT,
                        "Document content is immutable after upload");
            }
            return new DocumentUploadResponse(documentId, document.status(), existing.get().mediaType(),
                    existing.get().contentLengthBytes(), contentSha256);
        }
        if (document.status() != DocumentStatus.EXPECTED) {
            throw new LoanServiceException("DOCUMENT_NOT_UPLOADABLE", HttpStatus.CONFLICT,
                    "Document content can only be uploaded while metadata is EXPECTED");
        }
        repository.insertDocumentContent(document, contentSha256, content.length, "application/pdf", idempotencyKey,
                content);
        if (repository.markDocumentReceived(document.documentSk(), documentId, contentSha256, content.length,
                "application/pdf") != 1) {
            throw new LoanServiceException("DOCUMENT_STATUS_CONFLICT", HttpStatus.CONFLICT,
                    "Document status changed before content was stored");
        }
        repository.promoteWaitingWorkflow(document.applicationSk());
        repository.insertAudit(document.applicationSk(), externalId("AUD-"), principal.principalId(),
                "DOCUMENT_CONTENT_UPLOADED", "SUCCESS", "DOCUMENT", documentId, traceId());
        return new DocumentUploadResponse(documentId, DocumentStatus.RECEIVED, "application/pdf", content.length,
                contentSha256);
    }

    @Transactional(readOnly = true)
    public DocumentManifestResponse processingManifest(String applicationId, AuthenticatedPrincipal principal) {
        principals.requireIdentity(principal);
        authorizedApplication(applicationId, principal);
        List<ProcessingDocument> documents = repository.findReviewDocuments(applicationId).stream()
                .map(document -> new ProcessingDocument(document.documentId(), document.documentType(),
                        document.fileName(), document.status(), document.mediaType(), document.contentLengthBytes(),
                        document.contentSha256(), document.required()))
                .toList();
        return new DocumentManifestResponse(applicationId, documents);
    }

    @Transactional(readOnly = true)
    public byte[] documentContent(String applicationId, String documentId, AuthenticatedPrincipal principal) {
        principals.requireIdentity(principal);
        authorizedApplication(applicationId, principal);
        DocumentProcessingRow document = repository.findProcessingDocument(applicationId, documentId)
                .orElseThrow(this::notFound);
        return repository.findDocumentContent(document.documentSk()).orElseThrow(this::notFound).content();
    }

    @Transactional
    public DocumentUploadResponse transitionDocument(String applicationId, String documentId,
            DocumentStatusTransitionRequest request, AuthenticatedPrincipal principal) {
        if (!request.expectedStatus().canTransitionTo(request.targetStatus())) {
            throw new LoanServiceException("INVALID_DOCUMENT_STATUS_TRANSITION", HttpStatus.CONFLICT,
                    "The requested document status transition is not permitted");
        }
        principals.requireIdentity(principal);
        authorizedApplication(applicationId, principal);
        DocumentProcessingRow document = repository.findProcessingDocument(applicationId, documentId)
                .orElseThrow(this::notFound);
        if (!repository.auditEventExists(request.eventId())) {
            if (repository.updateDocumentStatus(document.documentSk(), request.expectedStatus(),
                    request.targetStatus()) != 1) {
                throw new LoanServiceException("STALE_DOCUMENT_STATUS", HttpStatus.CONFLICT,
                        "The document status changed before this request completed");
            }
            repository.insertAudit(document.applicationSk(), request.eventId(), principal.principalId(),
                    "DOCUMENT_STATUS_CHANGED", "SUCCESS", "DOCUMENT", documentId,
                    request.traceId() == null ? traceId() : request.traceId());
        }
        var content = repository.findDocumentContent(document.documentSk()).orElseThrow(this::notFound);
        return new DocumentUploadResponse(documentId, request.targetStatus(), content.mediaType(),
                content.contentLengthBytes(), content.contentSha256());
    }

    @Transactional
    public ApplicationResponse releaseWorkflow(String applicationId, AuthenticatedPrincipal principal) {
        principals.requireIdentity(principal);
        ApplicationRow application = authorizedApplication(applicationId, principal);
        if (repository.releaseDeferred(application.applicationSk()) == 0) {
            WorkflowRow current = repository.findWorkflow(application.applicationSk()).orElseThrow();
            if (current.status() != WorkflowDispatchStatus.PENDING
                    && current.status() != WorkflowDispatchStatus.IN_PROGRESS
                    && current.status() != WorkflowDispatchStatus.FAILED_RETRYABLE
                    && current.status() != WorkflowDispatchStatus.STARTED) {
                throw new LoanServiceException("WORKFLOW_NOT_RELEASABLE", HttpStatus.CONFLICT,
                        "The workflow cannot be started in its current state");
            }
        }
        return response(application);
    }

    @Transactional
    public ApplicationResponse transition(String applicationId, StatusTransitionRequest request,
            AuthenticatedPrincipal principal) {
        principals.requireIdentity(principal);
        ApplicationRow application = authorizedApplication(applicationId, principal);
        if (repository.auditEventExists(request.eventId())) {
            return response(application);
        }
        if (!request.expectedStatus().canTransitionTo(request.targetStatus())) {
            throw new LoanServiceException("INVALID_STATUS_TRANSITION", HttpStatus.CONFLICT,
                    "The requested status transition is not permitted");
        }
        if (repository.updateStatus(applicationId, request.expectedStatus(), request.targetStatus()) != 1) {
            throw new LoanServiceException("STALE_APPLICATION_STATUS", HttpStatus.CONFLICT,
                    "The application status changed before this request completed");
        }
        String traceId = request.traceId() == null ? traceId() : request.traceId();
        repository.insertAudit(application.applicationSk(), request.eventId(), principal.principalId(),
                "APPLICATION_STATUS_CHANGED", "SUCCESS", "LOAN_APPLICATION", applicationId, traceId);
        return response(repository.findByApplicationId(applicationId).orElseThrow());
    }

    private ApplicationResponse response(ApplicationRow application) {
        List<DocumentResponse> documents = repository.findDocuments(application.applicationSk()).stream()
                .map(document -> new DocumentResponse(document.documentId(), document.documentType(),
                        label(document.documentType()), document.fileName(), document.status(), document.required()))
                .toList();
        WorkflowRow workflow = repository.findWorkflow(application.applicationSk()).orElse(null);
        WorkflowResponse workflowResponse = workflow == null ? null
                : new WorkflowResponse(workflow.requestId(), workflow.workflowName(), workflow.workflowVersion(),
                        workflow.status(), workflow.engineWorkflowId(), workflow.lastErrorCode(),
                        workflow.lastErrorMessage());
        return new ApplicationResponse(application.applicationId(), application.scenarioId(),
                application.scenarioName(), application.status(), application.requestedAmount(),
                application.requestedTermMonths(), application.purposeCode(), documents, workflowResponse,
                workflow == null ? null : workflow.traceId(), application.createdAt(), application.updatedAt());
    }

    private ApplicationRow authorizedApplication(String applicationId, AuthenticatedPrincipal principal) {
        ApplicationRow application = repository.findByApplicationId(applicationId).orElseThrow(this::notFound);
        if (!repository.hasApplicationAccess(application.applicationSk(), principal.principalId())) {
            throw notFound();
        }
        return application;
    }

    private void validateRequest(CreateApplicationRequest request) {
        if (!TERMS.contains(request.loan().requestedTermMonths())) {
            throw new LoanServiceException("INVALID_TERM", HttpStatus.UNPROCESSABLE_CONTENT,
                    "Requested term must be 24, 36, 48, or 60 months");
        }
        if (!PURPOSES.contains(request.loan().purposeCode())) {
            throw new LoanServiceException("INVALID_PURPOSE", HttpStatus.UNPROCESSABLE_CONTENT,
                    "Requested purpose is not supported");
        }
        request.documents().forEach(this::validateDocument);
    }

    private void validateDocument(DocumentRequest document) {
        if (!DOCUMENT_TYPES.contains(document.documentType())) {
            throw new LoanServiceException("INVALID_DOCUMENT_TYPE", HttpStatus.UNPROCESSABLE_CONTENT,
                    "Document type is not supported");
        }
        if (document.status() != DocumentStatus.EXPECTED) {
            throw new LoanServiceException("INVALID_DOCUMENT_STATUS", HttpStatus.UNPROCESSABLE_CONTENT,
                    "Document metadata must be EXPECTED until PDF content is uploaded");
        }
    }

    private static void validatePrincipalCanCreate(AuthenticatedPrincipal principal) {
        if (!principal.hasRole("ROLE_APPLICANT") && !principal.hasRole("ROLE_LOAN_OFFICER")
                && !principal.hasRole("ROLE_ADMIN")) {
            throw new LoanServiceException("ACCESS_DENIED", HttpStatus.FORBIDDEN,
                    "The authenticated role cannot create applications");
        }
    }

    private WorkflowDispatchStatus initialDispatchStatus(CreateApplicationRequest request) {
        if (request.workflowStartMode() == WorkflowStartMode.DEFERRED) {
            return WorkflowDispatchStatus.DEFERRED;
        }
        boolean waiting = request.documents().stream()
                .anyMatch(document -> document.required() && document.status() == DocumentStatus.EXPECTED);
        return waiting ? WorkflowDispatchStatus.WAITING_FOR_DOCUMENTS : WorkflowDispatchStatus.PENDING;
    }

    private String workflowPayload(String applicationId, CreateApplicationRequest request, String traceId) {
        try {
            Map<String, Object> payload = new LinkedHashMap<>();
            payload.put("applicationId", applicationId);
            payload.put("traceId", traceId);
            if (StringUtils.hasText(request.scenarioId())) {
                payload.put("scenarioId", request.scenarioId());
            }
            if (StringUtils.hasText(request.scenarioName())) {
                payload.put("scenarioName", request.scenarioName());
            }
            if (request.documents() != null) {
                payload.put("documentCount", request.documents().size());
            }
            return canonicalMapper.writeValueAsString(payload);
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Unable to create safe workflow payload", exception);
        }
    }

    private String hash(Object request) {
        try {
            byte[] canonical = canonicalMapper.writeValueAsBytes(request);
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(canonical));
        } catch (JsonProcessingException | NoSuchAlgorithmException exception) {
            throw new IllegalStateException("Unable to hash intake request", exception);
        }
    }

    private static String hashBytes(byte[] content) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(content));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }

    private LoanServiceException notFound() {
        return new LoanServiceException("APPLICATION_NOT_FOUND", HttpStatus.NOT_FOUND,
                "The application was not found or is not accessible");
    }

    private static String externalId(String prefix) {
        return prefix + UUID.randomUUID();
    }

    private static String compactExternalId(String prefix) {
        return prefix + UUID.randomUUID().toString().replace("-", "");
    }

    private static String traceId() {
        return UUID.randomUUID().toString().replace("-", "");
    }

    private static String label(String code) {
        String normalized = code.toLowerCase().replace('_', ' ');
        return Character.toUpperCase(normalized.charAt(0)) + normalized.substring(1);
    }
}
