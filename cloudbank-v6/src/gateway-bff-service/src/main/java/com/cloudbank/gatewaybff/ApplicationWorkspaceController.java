// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.gatewaybff;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.servlet.http.HttpServletRequest;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.server.ResponseStatusException;

@RestController
class ApplicationWorkspaceController {
    private static final int MAX_DOCUMENT_BYTES = 25 * 1024 * 1024;
    private final SessionIdentity identity;
    private final RestClient loan;
    private final WorkspaceReadService reads;
    private final TraceReadService traces;

    ApplicationWorkspaceController(SessionIdentity identity,
            @Value("${cloudbank.bff.loan-base-url}") String baseUrl, RestClient.Builder builder,
            WorkspaceReadService reads, TraceReadService traces) {
        this.identity = identity;
        this.loan = builder.baseUrl(baseUrl).build();
        this.reads = reads;
        this.traces = traces;
    }

    @GetMapping("/bff/api/v1/applications/{applicationId}")
    ResponseEntity<Workspace> workspace(@PathVariable String applicationId,
            Authentication authentication, HttpServletRequest request) {
        String token = identity.require(authentication, request).accessToken();
        String correlationId = correlate(request);
        requireApplicationId(applicationId);
        try {
            OwnerWorkspace result = loan.get().uri("/api/v1/loan-applications/{id}/workspace", applicationId)
                    .headers(h -> h.setBearerAuth(token)).header("X-Correlation-ID", correlationId)
                    .retrieve().body(OwnerWorkspace.class);
            if (result == null || !applicationId.equals(result.applicationId()) || result.status() == null
                    || result.documents() == null || result.documents().size() > 100) {
                throw new ResponseStatusException(HttpStatus.BAD_GATEWAY);
            }
            var ids = new HashSet<String>();
            for (Document doc : result.documents()) {
                if (doc == null || doc.documentId() == null
                        || !doc.documentId().matches("DOC-[A-Za-z0-9][A-Za-z0-9-]{0,55}")
                        || !ids.add(doc.documentId()) || doc.documentType() == null || doc.fileName() == null
                        || doc.status() == null || (doc.contentAvailable()
                            && (!"application/pdf".equals(doc.mediaType()) || doc.contentLengthBytes() == null
                                || doc.contentLengthBytes() < 1 || doc.contentLengthBytes() > MAX_DOCUMENT_BYTES))) {
                    throw new ResponseStatusException(HttpStatus.BAD_GATEWAY);
                }
            }
            Overview overview = result.overview();
            Section<OverviewData> overviewSection = overview == null || overview.applicant() == null
                    || overview.loan() == null ? Section.unavailable("Applicant details are not available.")
                    : Section.available(new OverviewData(overview.applicant(), overview.loan(), result.status(),
                            result.createdAt(), result.updatedAt()));
            var sections = reads.compose(result.applicationId(), result.workflow() == null ? null : result.workflow().workflowId(),
                    result.workflow() == null ? null : result.workflow().dispatchStatus(), correlationId);
            var response = new Workspace(result.applicationId(), result.scenarioId(), result.scenarioName(),
                    result.status(), result.workflow() == null ? null : result.workflow().workflowId(), result.traceId(),
                    result.workflow() == null ? null : result.workflow().dispatchStatus(), correlationId,
                    "LIVE", Instant.now(), overviewSection,
                    Section.available(new Inventory(result.documents(), result.documentsTruncated())),
                    sections.ai(), sections.decision(), sections.policy(), sections.risk(), sections.workflow(),
                    audit(applicationId, token, correlationId),
                    traces.compose(result.applicationId(), result.workflow() == null ? null : result.workflow().workflowId(),
                            result.traceId()));
            return ResponseEntity.ok().header(HttpHeaders.CACHE_CONTROL, "private, no-store")
                    .header("X-Correlation-ID", correlationId).body(response);
        } catch (RestClientResponseException error) {
            throw failure(error.getStatusCode().value());
        } catch (RestClientException error) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE);
        }
    }

    private Section<WorkspaceReadModels.Audit> audit(String applicationId, String token, String correlationId) {
        try {
            var result = loan.get().uri("/api/v1/loan-applications/{id}/audit", applicationId)
                    .headers(h -> h.setBearerAuth(token)).header("X-Correlation-ID", correlationId)
                    .retrieve().body(WorkspaceReadModels.Audit.class);
            if (result == null || !applicationId.equals(result.applicationId()) || result.items() == null
                    || result.items().size() > 100 || result.truncated() == null) {
                return Section.error();
            }
            var ids = new HashSet<String>();
            for (var event : result.items()) {
                if (event == null || event.eventId() == null || !event.eventId().matches("AUDIT-[1-9][0-9]{0,17}")
                        || !ids.add(event.eventId()) || event.occurredAt() == null
                        || event.action() == null || !Set.of("INTAKE_CREATED", "DOCUMENT_METADATA_REGISTERED",
                            "DOCUMENT_CONTENT_UPLOADED", "DOCUMENT_STATUS_CHANGED", "APPLICATION_STATUS_CHANGED",
                            "DECISION_RECORDED", "OTHER_EVENT").contains(event.action())
                        || event.actionLabel() == null || !Set.of("Application created", "Document registered",
                            "Document uploaded", "Document status changed", "Application status changed",
                            "Decision recorded", "Recorded event").contains(event.actionLabel())
                        || event.actorLabel() == null || !Set.of("Current user", "Recorded actor", "Not recorded")
                            .contains(event.actorLabel())
                        || event.outcome() == null || !Set.of("SUCCESS", "DENIED", "ERROR").contains(event.outcome())
                        || event.objectType() == null || !Set.of("LOAN_APPLICATION", "DOCUMENT", "OTHER")
                            .contains(event.objectType())
                        || (event.objectId() != null && !("LOAN_APPLICATION".equals(event.objectType())
                            && applicationId.equals(event.objectId())) && !("DOCUMENT".equals(event.objectType())
                            && event.objectId().matches("DOC-[A-Za-z0-9][A-Za-z0-9-]{0,55}")))
                        || (event.traceId() != null && !event.traceId().matches("[0-9a-fA-F]{32}"))) {
                    return Section.error();
                }
            }
            return Section.available(result);
        } catch (RestClientResponseException error) {
            int status = error.getStatusCode().value();
            if (status == 403) throw failure(status);
            return status == 404 ? Section.missing("Recorded application events are not available.") : Section.error();
        } catch (RestClientException error) {
            return Section.error();
        }
    }

    @GetMapping("/bff/api/v1/applications/{applicationId}/documents/{documentId}/content")
    ResponseEntity<byte[]> content(@PathVariable String applicationId, @PathVariable String documentId,
            Authentication authentication, HttpServletRequest request) {
        String token = identity.require(authentication, request).accessToken();
        String correlationId = correlate(request);
        requireApplicationId(applicationId);
        if (!documentId.matches("DOC-[A-Za-z0-9][A-Za-z0-9-]{0,55}")) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST);
        }
        try {
            return loan.get().uri("/api/v1/loan-applications/{id}/documents/{doc}/content", applicationId, documentId)
                    .headers(h -> h.setBearerAuth(token)).header("X-Correlation-ID", correlationId)
                    .accept(MediaType.APPLICATION_PDF).exchange((outgoing, incoming) -> {
                        if (incoming.getStatusCode().value() != 200) {
                            throw failure(incoming.getStatusCode().value());
                        }
                        MediaType type = incoming.getHeaders().getContentType();
                        long length = incoming.getHeaders().getContentLength();
                        if (type == null || !"application".equals(type.getType()) || !"pdf".equals(type.getSubtype())
                                || length == 0 || length > MAX_DOCUMENT_BYTES) {
                            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY);
                        }
                        byte[] bytes = incoming.getBody().readNBytes(MAX_DOCUMENT_BYTES + 1);
                        if (bytes.length == 0 || bytes.length > MAX_DOCUMENT_BYTES
                                || (length >= 0 && length != bytes.length)) {
                            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY);
                        }
                        String name = incoming.getHeaders().getContentDisposition().getFilename();
                        name = name == null || name.isBlank() ? "document.pdf"
                                : name.replaceAll("[\\p{Cntrl}]", "_").replace('/', '_').replace('\\', '_');
                        return ResponseEntity.ok().contentType(MediaType.APPLICATION_PDF).contentLength(bytes.length)
                                .header(HttpHeaders.CONTENT_DISPOSITION, ContentDisposition.inline()
                                        .filename(name, StandardCharsets.UTF_8).build().toString())
                                .header(HttpHeaders.CACHE_CONTROL, "private, no-store")
                                .header("X-Content-Type-Options", "nosniff")
                                .header("X-Correlation-ID", correlationId).body(bytes);
                    });
        } catch (IllegalArgumentException invalidHeaders) {
            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY);
        } catch (RestClientException error) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE);
        }
    }

    private static String correlate(HttpServletRequest request) {
        String id = UUID.randomUUID().toString();
        request.setAttribute("bffCorrelationId", id);
        return id;
    }

    private static void requireApplicationId(String id) {
        if (!id.matches("APP-[A-Za-z0-9][A-Za-z0-9-]{0,35}")) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST);
        }
    }

    private static ResponseStatusException failure(int status) {
        return new ResponseStatusException(switch (status) {
            case 400 -> HttpStatus.BAD_REQUEST;
            case 403 -> HttpStatus.FORBIDDEN;
            case 404 -> HttpStatus.NOT_FOUND;
            case 503 -> HttpStatus.SERVICE_UNAVAILABLE;
            default -> HttpStatus.BAD_GATEWAY;
        });
    }

    record Section<T>(String availability, T data, String code, String message) {
        static <T> Section<T> available(T data) { return new Section<>("AVAILABLE", data, null, null); }
        static <T> Section<T> unavailable(String message) {
            return new Section<>("UNAVAILABLE", null, "NOT_IMPLEMENTED", message);
        }
        static <T> Section<T> pending(String message) { return new Section<>("PENDING", null, "RESULT_PENDING", message); }
        static <T> Section<T> missing(String message) { return new Section<>("UNAVAILABLE", null, "RESULT_UNAVAILABLE", message); }
        static <T> Section<T> error() { return new Section<>("ERROR", null, "UPSTREAM_READ_FAILED",
                "This result could not be read. Reload data to request it again."); }
    }
    record Workspace(String applicationId, String scenarioId, String scenarioName, String status,
            String workflowId, String traceId, String dispatchStatus, String correlationId, String source,
            Instant snapshotAt, Section<OverviewData> overview, Section<Inventory> documents,
            Section<WorkspaceReadModels.AiTasks> aiWorkflowTasks, Section<WorkspaceReadModels.Decisions> decision,
            Section<WorkspaceReadModels.PolicyEvidence> policyEvidence, Section<WorkspaceReadModels.Risks> riskSignals,
            Section<WorkspaceReadModels.Workflow> workflow, Section<WorkspaceReadModels.Audit> audit,
            Section<WorkspaceReadModels.Trace> trace) { }
    record OverviewData(Applicant applicant, Loan loan, String status, Instant createdAt, Instant updatedAt) { }
    record Inventory(List<Document> items, boolean truncated) { }

    @JsonIgnoreProperties(ignoreUnknown = true)
    record OwnerWorkspace(String applicationId, String scenarioId, String scenarioName, String status,
            Overview overview, List<Document> documents, boolean documentsTruncated, Workflow workflow,
            String traceId, Instant createdAt, Instant updatedAt) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record Overview(Applicant applicant, Loan loan) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record Applicant(String displayName, String phoneToken, String emailToken, String ageBand, Address address) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record Address(String addressLine, String locality, String jurisdictionCode, String addressToken,
            String countryCode, String postalCode) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record Loan(BigDecimal requestedAmount, Integer requestedTermMonths, String purposeCode, String policyVersion) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record Document(String documentId, String documentType, String documentLabel, String fileName, String status,
            boolean required, boolean contentAvailable, String mediaType, Long contentLengthBytes,
            String contentSha256) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record Workflow(String dispatchStatus, String workflowId) { }
}
