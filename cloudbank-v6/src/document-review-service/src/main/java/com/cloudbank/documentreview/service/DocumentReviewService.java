// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentreview.service;

import com.cloudbank.documentreview.api.DocumentReviewApiModels.DocumentReviewRequest;
import com.cloudbank.documentreview.client.DocumentIngestClient;
import com.cloudbank.documentreview.client.LoanApplicationClient;
import com.cloudbank.documentreview.domain.ReviewModels.DocumentManifest;
import com.cloudbank.documentreview.domain.ReviewModels.ExtractionReviewInput;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewResult;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewStatus;
import com.cloudbank.documentreview.persistence.DocumentReviewRepository;
import com.cloudbank.documentreview.rules.DocumentReviewV2Profile;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DocumentReviewService {
    private final LoanApplicationClient loan;
    private final DocumentIngestClient ingest;
    private final DocumentReviewRepository repository;
    private final DocumentReviewV2Profile profile;
    private final ReviewFingerprintService fingerprints;
    private final DocumentReviewPersistenceService persistence;
    private final DocumentStatusAcknowledgementService acknowledgements;
    private final ObjectMapper json;

    public DocumentReviewService(LoanApplicationClient loan, DocumentIngestClient ingest,
            DocumentReviewRepository repository, DocumentReviewV2Profile profile, ReviewFingerprintService fingerprints,
            DocumentReviewPersistenceService persistence, DocumentStatusAcknowledgementService acknowledgements,
            ObjectMapper json) {
        this.loan = loan;
        this.ingest = ingest;
        this.repository = repository;
        this.profile = profile;
        this.fingerprints = fingerprints;
        this.persistence = persistence;
        this.acknowledgements = acknowledgements;
        this.json = json;
    }

    public ReviewResult review(DocumentReviewRequest request, String idempotencyKey) {
        String idempotencyHash = fingerprints.sha256(idempotencyKey);
        String requestHash = hash(request);
        var existing = repository.findByIdempotencyHash(idempotencyHash);
        if (existing.isPresent()) {
            if (!existing.get().requestHash().equals(requestHash))
                throw new ReviewServiceException("IDEMPOTENCY_KEY_CONFLICT", HttpStatus.CONFLICT,
                        "Idempotency key was used with a different request.", false);
            ReviewResult result = existing.get().result();
            if (result.reviewStatus() == ReviewStatus.COMPLETED)
                return result;
            return acknowledgeExisting(result);
        }
        DocumentManifest manifest = required(loan.manifest(request.applicationId()), "DOCUMENT_MANIFEST_INVALID");
        ExtractionReviewInput input = required(ingest.reviewInput(request.applicationId()),
                "EXTRACTION_REVIEW_INPUT_INVALID");
        if (!request.applicationId().equals(manifest.applicationId())
                || !request.applicationId().equals(input.applicationId())) {
            throw new ReviewServiceException("APPLICATION_CONTEXT_MISMATCH", HttpStatus.BAD_GATEWAY,
                    "Upstream application context does not match the review request.", false);
        }
        String reviewId = fingerprints.reviewId(request.applicationId(), DocumentReviewV2Profile.VERSION,
                idempotencyKey);
        ReviewResult result = profile.evaluate(reviewId, request.applicationId(), request.workflowId(),
                request.taskReference(), request.traceId(), manifest, input);
        persistence.persistPending(result, input, idempotencyHash, requestHash,
                fingerprints.sha256(canonical(manifest) + canonical(input) + DocumentReviewV2Profile.VERSION));
        return acknowledgements.acknowledge(result, manifest);
    }

    @Transactional(readOnly = true)
    public ReviewResult get(String reviewId) {
        return repository.findByReviewId(reviewId)
                .orElseThrow(() -> new ReviewServiceException("DOCUMENT_REVIEW_NOT_FOUND", HttpStatus.NOT_FOUND,
                        "Document review was not found.", false));
    }

    @Transactional(readOnly = true)
    public ReviewResult latest(String applicationId) {
        return repository.findLatest(applicationId)
                .orElseThrow(() -> new ReviewServiceException("DOCUMENT_REVIEW_NOT_FOUND", HttpStatus.NOT_FOUND,
                        "Document review was not found.", false));
    }

    private ReviewResult acknowledgeExisting(ReviewResult result) {
        DocumentManifest manifest = required(loan.manifest(result.applicationId()), "DOCUMENT_MANIFEST_INVALID");
        return acknowledgements.acknowledge(result, manifest);
    }

    private <T> T required(T value, String code) {
        if (value == null)
            throw new ReviewServiceException(code, HttpStatus.BAD_GATEWAY,
                    "Upstream response did not satisfy the review contract.", false);
        return value;
    }

    private String hash(Object value) {
        return fingerprints.sha256(canonical(value));
    }

    private String canonical(Object value) {
        try {
            return json.writeValueAsString(value);
        } catch (JacksonException exception) {
            throw new IllegalStateException("Review input could not be serialized", exception);
        }
    }
}
