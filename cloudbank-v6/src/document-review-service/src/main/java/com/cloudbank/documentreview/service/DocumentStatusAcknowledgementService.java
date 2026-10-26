// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentreview.service;

import com.cloudbank.documentreview.client.LoanApplicationClient;
import com.cloudbank.documentreview.domain.ReviewModels.DocumentManifest;
import com.cloudbank.documentreview.domain.ReviewModels.ManifestDocument;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewResult;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewedDocument;
import com.cloudbank.documentreview.persistence.DocumentReviewRepository;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.client.RestClientResponseException;

@Service
public class DocumentStatusAcknowledgementService {
    private static final Logger LOGGER = LoggerFactory.getLogger(DocumentStatusAcknowledgementService.class);

    private final LoanApplicationClient loan;
    private final DocumentReviewRepository repository;
    private final ReviewFingerprintService fingerprint;

    public DocumentStatusAcknowledgementService(LoanApplicationClient loan, DocumentReviewRepository repository,
            ReviewFingerprintService fingerprint) {
        this.loan = loan;
        this.repository = repository;
        this.fingerprint = fingerprint;
    }

    @Transactional
    public ReviewResult acknowledge(ReviewResult result, DocumentManifest manifest) {
        Map<String, String> statuses = manifest.documents().stream()
                .collect(java.util.stream.Collectors.toMap(ManifestDocument::documentId, ManifestDocument::status));
        String documentId = null;
        String targetStatus = null;
        try {
            for (ReviewedDocument acknowledgement : result.acknowledgements()) {
                documentId = acknowledgement.documentId();
                targetStatus = acknowledgement.targetStatus();
                loan.transitionStatus(result.applicationId(), acknowledgement.documentId(),
                        statuses.get(acknowledgement.documentId()), acknowledgement.targetStatus(),
                        "DREVSTAT-" + fingerprint.sha256(result.reviewId() + ":" + acknowledgement.documentId() + ":"
                                + acknowledgement.targetStatus()),
                        result.traceId());
            }
            repository.markCompleted(result);
            return repository.findByReviewId(result.reviewId()).orElseThrow();
        } catch (RuntimeException exception) {
            int downstreamStatus = exception instanceof RestClientResponseException response
                    ? response.getStatusCode().value()
                    : 0;
            LOGGER.warn(
                    "Document status acknowledgement failed applicationId={} reviewId={} documentId={} targetStatus={} downstreamStatus={} exceptionType={}",
                    result.applicationId(), result.reviewId(), documentId, targetStatus, downstreamStatus,
                    exception.getClass().getSimpleName());
            throw new ReviewServiceException("DOCUMENT_STATUS_ACKNOWLEDGEMENT_FAILED",
                    org.springframework.http.HttpStatus.SERVICE_UNAVAILABLE,
                    "Document status acknowledgement is pending.", true, exception);
        }
    }
}
