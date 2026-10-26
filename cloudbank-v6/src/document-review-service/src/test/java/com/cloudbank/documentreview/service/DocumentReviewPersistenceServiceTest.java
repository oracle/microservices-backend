// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentreview.service;

import static org.mockito.Mockito.verify;

import com.cloudbank.documentreview.domain.ReviewModels.DocumentCounts;
import com.cloudbank.documentreview.domain.ReviewModels.ExtractionReviewInput;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewDisposition;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewResult;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewStatus;
import com.cloudbank.documentreview.persistence.DocumentReviewRepository;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class DocumentReviewPersistenceServiceTest {
    @Mock
    private DocumentReviewRepository repository;
    @InjectMocks
    private DocumentReviewPersistenceService service;

    @Test
    void persistsPendingReviewAndProjectionsTogether() {
        ReviewResult result = new ReviewResult("DREV-00000000000000000000000000000000", "APP-ONE", "WF-ONE",
                "review_documents", ReviewStatus.ACK_PENDING, ReviewDisposition.CLEAR, "document-review-v1",
                new DocumentCounts(0, 0, 0, 0, 0), List.of(), "0123456789abcdef0123456789abcdef",
                List.of());
        ExtractionReviewInput input = new ExtractionReviewInput("APP-ONE", List.of());

        service.persistPending(result, input, "idempotency-hash", "request-hash", "input-fingerprint");

        verify(repository).persist(result, "idempotency-hash", "request-hash", "input-fingerprint");
        verify(repository).persistProjections(result, input);
    }
}
