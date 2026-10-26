// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.api;

import static com.cloudbank.loanapplication.api.ApplicationApiModels.ApplicationResponse;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.ApplicationPageResponse;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.CreateApplicationRequest;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.DocumentManifestResponse;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.DocumentStatusTransitionRequest;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.DocumentUploadResponse;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.RegisterDocumentsRequest;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.StatusTransitionRequest;

import com.cloudbank.loanapplication.domain.ApplicationStatus;
import com.cloudbank.loanapplication.security.AuthenticatedPrincipal;
import com.cloudbank.loanapplication.service.LoanApplicationService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Pattern;
import jakarta.servlet.http.HttpServletRequest;
import java.io.IOException;
import java.net.URI;
import org.springframework.http.ResponseEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@Validated
@RequestMapping
public class LoanApplicationController {

    private static final String IDEMPOTENCY_PATTERN = "[A-Za-z0-9._:-]{8,200}";
    private static final String APPLICATION_ID_PATTERN = "APP-[A-Za-z0-9][A-Za-z0-9-]{0,35}";
    private static final String DOCUMENT_ID_PATTERN = "DOC-[A-Za-z0-9][A-Za-z0-9-]{0,55}";
    private static final int MAX_DOCUMENT_BYTES = 25 * 1024 * 1024;

    private final LoanApplicationService service;

    public LoanApplicationController(LoanApplicationService service) {
        this.service = service;
    }

    @PostMapping("/api/v1/loan-applications")
    @PreAuthorize("hasAuthority('SCOPE_cloudbank.write') and hasAnyRole('APPLICANT','LOAN_OFFICER','ADMIN')")
    public ResponseEntity<ApplicationResponse> create(
            @RequestHeader("Idempotency-Key") @Pattern(regexp = IDEMPOTENCY_PATTERN) String idempotencyKey,
            @Valid @RequestBody CreateApplicationRequest request,
            JwtAuthenticationToken authentication) {
        ApplicationResponse response = service.create(request, idempotencyKey,
                AuthenticatedPrincipal.from(authentication.getToken()));
        return ResponseEntity.accepted()
                .location(URI.create("/api/v1/loan-applications/" + response.applicationId()))
                .body(response);
    }

    @GetMapping("/api/v1/loan-applications/{applicationId}")
    @PreAuthorize("hasAuthority('SCOPE_cloudbank.read') and "
            + "hasAnyRole('APPLICANT','LOAN_OFFICER','UNDERWRITER','AUDITOR','ADMIN')")
    public ApplicationResponse get(
            @PathVariable @Pattern(regexp = APPLICATION_ID_PATTERN,
                    message = "must be a valid CloudBank application ID") String applicationId,
            JwtAuthenticationToken authentication) {
        return service.get(applicationId, AuthenticatedPrincipal.from(authentication.getToken()));
    }

    @GetMapping("/api/v1/loan-applications")
    @PreAuthorize("hasAuthority('SCOPE_cloudbank.read') and "
            + "hasAnyRole('APPLICANT','LOAN_OFFICER','UNDERWRITER','AUDITOR','ADMIN')")
    public ApplicationPageResponse list(
            @RequestParam(required = false) ApplicationStatus status,
            @RequestParam(required = false) String scenarioId,
            @RequestParam(defaultValue = "0") @Min(0) int page,
            @RequestParam(defaultValue = "20") @Min(1) @Max(100) int size,
            JwtAuthenticationToken authentication) {
        return service.list(status, scenarioId, page, size,
                AuthenticatedPrincipal.from(authentication.getToken()));
    }

    @PostMapping("/api/v1/loan-applications/{applicationId}/documents")
    @PreAuthorize("hasAuthority('SCOPE_cloudbank.write') and hasAnyRole('APPLICANT','LOAN_OFFICER','ADMIN')")
    public ResponseEntity<ApplicationResponse> registerDocuments(
            @PathVariable @Pattern(regexp = APPLICATION_ID_PATTERN,
                    message = "must be a valid CloudBank application ID") String applicationId,
            @RequestHeader("Idempotency-Key") @Pattern(regexp = IDEMPOTENCY_PATTERN) String idempotencyKey,
            @Valid @RequestBody RegisterDocumentsRequest request,
            JwtAuthenticationToken authentication) {
        return ResponseEntity.accepted().body(service.registerDocuments(applicationId, request, idempotencyKey,
                AuthenticatedPrincipal.from(authentication.getToken())));
    }

    @PutMapping(path = "/api/v1/loan-applications/{applicationId}/documents/{documentId}/content",
            consumes = MediaType.APPLICATION_PDF_VALUE)
    @PreAuthorize("hasAuthority('SCOPE_cloudbank.write') and hasAnyRole('APPLICANT','LOAN_OFFICER','ADMIN')")
    public DocumentUploadResponse uploadDocumentContent(
            @PathVariable @Pattern(regexp = APPLICATION_ID_PATTERN,
                    message = "must be a valid CloudBank application ID") String applicationId,
            @PathVariable @Pattern(regexp = DOCUMENT_ID_PATTERN,
                    message = "must be a valid CloudBank document ID") String documentId,
            @RequestHeader("Idempotency-Key") @Pattern(regexp = IDEMPOTENCY_PATTERN) String idempotencyKey,
            @RequestHeader(HttpHeaders.CONTENT_TYPE) String mediaType,
            JwtAuthenticationToken authentication,
            HttpServletRequest request) throws IOException {
        byte[] content = request.getInputStream().readNBytes(MAX_DOCUMENT_BYTES + 1);
        return service.uploadDocumentContent(applicationId, documentId, idempotencyKey,
                mediaType, content, AuthenticatedPrincipal.from(authentication.getToken()));
    }

    @GetMapping("/internal/api/v1/loan-applications/{applicationId}/documents")
    @PreAuthorize("@loanAuthorization.isInternal(authentication)")
    public DocumentManifestResponse processingManifest(
            @PathVariable @Pattern(regexp = APPLICATION_ID_PATTERN,
                    message = "must be a valid CloudBank application ID") String applicationId,
            JwtAuthenticationToken authentication) {
        return service.processingManifest(applicationId,
                AuthenticatedPrincipal.from(authentication.getToken()));
    }

    @GetMapping("/internal/api/v1/loan-applications/{applicationId}/documents/{documentId}/content")
    @PreAuthorize("@loanAuthorization.isInternal(authentication)")
    public ResponseEntity<byte[]> documentContent(
            @PathVariable @Pattern(regexp = APPLICATION_ID_PATTERN,
                    message = "must be a valid CloudBank application ID") String applicationId,
            @PathVariable @Pattern(regexp = DOCUMENT_ID_PATTERN,
                    message = "must be a valid CloudBank document ID") String documentId,
            JwtAuthenticationToken authentication) {
        byte[] content = service.documentContent(applicationId, documentId,
                AuthenticatedPrincipal.from(authentication.getToken()));
        return ResponseEntity.ok()
                .contentType(MediaType.APPLICATION_PDF)
                .contentLength(content.length)
                .header(HttpHeaders.CACHE_CONTROL, "private, no-store")
                .body(content);
    }

    @PostMapping("/internal/api/v1/loan-applications/{applicationId}/documents/{documentId}/status-transitions")
    @PreAuthorize("@loanAuthorization.isInternal(authentication)")
    public DocumentUploadResponse transitionDocument(
            @PathVariable @Pattern(regexp = APPLICATION_ID_PATTERN,
                    message = "must be a valid CloudBank application ID") String applicationId,
            @PathVariable @Pattern(regexp = DOCUMENT_ID_PATTERN,
                    message = "must be a valid CloudBank document ID") String documentId,
            @Valid @RequestBody DocumentStatusTransitionRequest request,
            JwtAuthenticationToken authentication) {
        return service.transitionDocument(applicationId, documentId, request,
                AuthenticatedPrincipal.from(authentication.getToken()));
    }

    @PostMapping("/api/v1/loan-applications/{applicationId}/workflow-start")
    @PreAuthorize("hasAuthority('SCOPE_cloudbank.write') and hasAnyRole('APPLICANT','LOAN_OFFICER','ADMIN')")
    public ResponseEntity<ApplicationResponse> releaseWorkflow(
            @PathVariable @Pattern(regexp = APPLICATION_ID_PATTERN,
                    message = "must be a valid CloudBank application ID") String applicationId,
            JwtAuthenticationToken authentication) {
        return ResponseEntity.accepted().body(service.releaseWorkflow(applicationId,
                AuthenticatedPrincipal.from(authentication.getToken())));
    }

    @PostMapping("/internal/api/v1/loan-applications/{applicationId}/status-transitions")
    @PreAuthorize("@loanAuthorization.isInternal(authentication)")
    public ApplicationResponse transition(
            @PathVariable @Pattern(regexp = APPLICATION_ID_PATTERN,
                    message = "must be a valid CloudBank application ID") String applicationId,
            @Valid @RequestBody StatusTransitionRequest request,
            JwtAuthenticationToken authentication) {
        return service.transition(applicationId, request,
                AuthenticatedPrincipal.from(authentication.getToken()));
    }
}
