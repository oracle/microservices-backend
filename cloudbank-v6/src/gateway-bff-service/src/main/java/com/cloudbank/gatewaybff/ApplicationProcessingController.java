// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.gatewaybff;

import com.cloudbank.gatewaybff.ApplicationCreationController.CreationResponse;
import com.cloudbank.gatewaybff.ApplicationCreationController.LoanCreationResponse;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.servlet.http.HttpServletRequest;
import java.io.IOException;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.server.ResponseStatusException;

@RestController
class ApplicationProcessingController {
    private static final int MAX_DOCUMENT_BYTES = 25 * 1024 * 1024;
    private final SessionIdentity identity;
    private final RestClient loan;

    ApplicationProcessingController(SessionIdentity identity,
            @Value("${cloudbank.bff.loan-base-url}") String loanBaseUrl, RestClient.Builder builder) {
        this.identity = identity;
        this.loan = builder.baseUrl(loanBaseUrl).build();
    }

    @PutMapping("/bff/api/v1/applications/{applicationId}/documents/{documentId}/content")
    ResponseEntity<UploadResponse> upload(@PathVariable String applicationId, @PathVariable String documentId,
            @RequestHeader("Idempotency-Key") String key,
            @RequestHeader("Content-Type") String mediaType,
            Authentication authentication, HttpServletRequest request) throws IOException {
        String token = identity.requireWrite(authentication, request).accessToken();
        String correlationId = correlate(request);
        requireApplicationId(applicationId);
        if (!documentId.matches("DOC-[A-Za-z0-9][A-Za-z0-9-]{0,55}")
                || !key.matches("[A-Za-z0-9._:-]{8,200}")) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST);
        }
        if (!isPdf(mediaType)) {
            throw new ResponseStatusException(HttpStatus.UNSUPPORTED_MEDIA_TYPE);
        }
        if (request.getContentLengthLong() > MAX_DOCUMENT_BYTES) {
            throw new ResponseStatusException(HttpStatus.CONTENT_TOO_LARGE);
        }
        // Read at most one byte beyond the owner-service limit, including chunked requests.
        byte[] content = request.getInputStream().readNBytes(MAX_DOCUMENT_BYTES + 1);
        if (content.length == 0 || content.length > MAX_DOCUMENT_BYTES) {
            throw new ResponseStatusException(HttpStatus.CONTENT_TOO_LARGE);
        }
        try {
            StoredUpload result = loan.put()
                    .uri("/api/v1/loan-applications/{applicationId}/documents/{documentId}/content",
                            applicationId, documentId)
                    .headers(headers -> headers.setBearerAuth(token))
                    .header("Idempotency-Key", key).header("X-Correlation-ID", correlationId)
                    .contentType(MediaType.APPLICATION_PDF).body(content).retrieve().body(StoredUpload.class);
            if (result == null || !documentId.equals(result.documentId()) || result.status() == null
                    || !MediaType.APPLICATION_PDF_VALUE.equals(result.mediaType())
                    || result.contentLengthBytes() != content.length || result.contentSha256() == null
                    || !result.contentSha256().matches("[0-9a-fA-F]{64}")) {
                throw new ResponseStatusException(HttpStatus.BAD_GATEWAY);
            }
            return ResponseEntity.ok().header("Cache-Control", "no-store")
                    .header("X-Correlation-ID", correlationId)
                    .body(new UploadResponse(result.documentId(), result.status(), result.mediaType(),
                            result.contentLengthBytes(), result.contentSha256(), correlationId));
        } catch (RestClientResponseException error) {
            throw upstreamFailure(error);
        } catch (RestClientException error) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE);
        }
    }

    @PostMapping("/bff/api/v1/applications/{applicationId}/workflow-start")
    ResponseEntity<CreationResponse> start(@PathVariable String applicationId,
            Authentication authentication, HttpServletRequest request) throws IOException {
        String token = identity.requireWrite(authentication, request).accessToken();
        String correlationId = correlate(request);
        requireApplicationId(applicationId);
        if (request.getInputStream().read() != -1) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST);
        }
        try {
            LoanCreationResponse result = loan.post()
                    .uri("/api/v1/loan-applications/{applicationId}/workflow-start", applicationId)
                    .headers(headers -> headers.setBearerAuth(token))
                    .header("X-Correlation-ID", correlationId).retrieve().body(LoanCreationResponse.class);
            if (result == null || !applicationId.equals(result.applicationId()) || result.status() == null
                    || result.workflow() == null || result.workflow().dispatchStatus() == null
                    || result.documents() == null) {
                throw new ResponseStatusException(HttpStatus.BAD_GATEWAY);
            }
            return ResponseEntity.accepted().header("Cache-Control", "no-store")
                    .header("X-Correlation-ID", correlationId)
                    .body(new CreationResponse(result.applicationId(), result.scenarioId(), result.scenarioName(),
                            result.status(), result.requestedAmount(), result.requestedTermMonths(),
                            result.purposeCode(), result.createdAt(), result.documents(), result.workflow(),
                            result.traceId(), correlationId));
        } catch (RestClientResponseException error) {
            throw upstreamFailure(error);
        } catch (RestClientException error) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE);
        }
    }

    private static String correlate(HttpServletRequest request) {
        String id = UUID.randomUUID().toString();
        request.setAttribute("bffCorrelationId", id);
        return id;
    }

    private static boolean isPdf(String value) {
        try {
            MediaType mediaType = MediaType.parseMediaType(value);
            return "application".equalsIgnoreCase(mediaType.getType())
                    && "pdf".equalsIgnoreCase(mediaType.getSubtype());
        } catch (IllegalArgumentException invalid) {
            return false;
        }
    }

    private static void requireApplicationId(String id) {
        if (!id.matches("APP-[A-Za-z0-9][A-Za-z0-9-]{0,35}")) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST);
        }
    }

    private static ResponseStatusException upstreamFailure(RestClientResponseException error) {
        HttpStatus status = switch (error.getStatusCode().value()) {
            case 400 -> HttpStatus.BAD_REQUEST;
            case 403 -> HttpStatus.FORBIDDEN;
            case 404 -> HttpStatus.NOT_FOUND;
            case 409 -> HttpStatus.CONFLICT;
            case 413 -> HttpStatus.CONTENT_TOO_LARGE;
            case 415 -> HttpStatus.UNSUPPORTED_MEDIA_TYPE;
            case 422 -> HttpStatus.UNPROCESSABLE_CONTENT;
            case 503 -> HttpStatus.SERVICE_UNAVAILABLE;
            default -> HttpStatus.BAD_GATEWAY;
        };
        return new ResponseStatusException(status);
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    record StoredUpload(String documentId, String status, String mediaType, long contentLengthBytes,
            String contentSha256) { }

    record UploadResponse(String documentId, String status, String mediaType, long contentLengthBytes,
            String contentSha256, String correlationId) { }
}
