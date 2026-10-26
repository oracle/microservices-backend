// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentreview.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.cloudbank.documentreview.client.LoanApplicationClient;
import com.cloudbank.documentreview.domain.ReviewModels.DocumentCounts;
import com.cloudbank.documentreview.domain.ReviewModels.DocumentManifest;
import com.cloudbank.documentreview.domain.ReviewModels.ManifestDocument;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewDisposition;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewResult;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewStatus;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewedDocument;
import com.cloudbank.documentreview.persistence.DocumentReviewRepository;
import java.util.List;
import java.util.Optional;
import java.util.function.Supplier;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;

@ExtendWith(MockitoExtension.class)
class DocumentStatusAcknowledgementServiceTest {
    @Mock
    private LoanApplicationClient loan;
    @Mock
    private DocumentReviewRepository repository;
    @Mock
    private ReviewFingerprintService fingerprints;

    private DocumentStatusAcknowledgementService service;

    @BeforeEach
    void setUp() {
        service = new DocumentStatusAcknowledgementService(loan, repository, fingerprints);
    }

    @Test
    void transitionsEachExtractedDocumentWithADeterministicEventIdThenMarksComplete() {
        ReviewResult pending = pending("DOC-ONE", "VALIDATED");
        ReviewResult completed = completed();
        when(fingerprints.sha256(anyString())).thenReturn("event-hash");
        when(repository.findByReviewId(pending.reviewId())).thenReturn(Optional.of(completed));

        assertThat(service.acknowledge(pending, manifest())).isSameAs(completed);

        verify(loan).transitionStatus("APP-ONE", "DOC-ONE", "EXTRACTED", "VALIDATED", "DREVSTAT-event-hash",
                "0123456789abcdef0123456789abcdef");
        verify(repository).markCompleted(pending);
    }

    @Test
    void partialAcknowledgementFailureLeavesTheReviewPendingForRetry() {
        ReviewResult pending = pending("DOC-ONE", "NEEDS_REVIEW", "DOC-TWO", "NEEDS_REVIEW");
        when(fingerprints.sha256(anyString())).thenReturn("event-hash");
        doNothing().when(loan).transitionStatus("APP-ONE", "DOC-ONE", "EXTRACTED", "NEEDS_REVIEW",
                "DREVSTAT-event-hash", "0123456789abcdef0123456789abcdef");
        doThrow(new IllegalStateException("downstream unavailable")).when(loan).transitionStatus("APP-ONE", "DOC-TWO",
                "EXTRACTED", "NEEDS_REVIEW", "DREVSTAT-event-hash", "0123456789abcdef0123456789abcdef");

        assertThatThrownBy(() -> service.acknowledge(pending, manifest())).isInstanceOf(ReviewServiceException.class)
                .satisfies(exception -> {
                    ReviewServiceException review = (ReviewServiceException) exception;
                    assertThat(review.code()).isEqualTo("DOCUMENT_STATUS_ACKNOWLEDGEMENT_FAILED");
                    assertThat(review.status()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
                    assertThat(review.retryable()).isTrue();
                    assertThat(review.getCause()).isInstanceOf(IllegalStateException.class)
                            .hasMessage("downstream unavailable");
                });

        verify(repository, never()).markCompleted(any());
    }

    private static Supplier<?> anySupplier() {
        return any();
    }

    private static DocumentManifest manifest() {
        return new DocumentManifest("APP-ONE",
                List.of(new ManifestDocument("DOC-ONE", "PAY_STATEMENT", "EXTRACTED", true),
                        new ManifestDocument("DOC-TWO", "PAY_STATEMENT", "EXTRACTED", true)));
    }

    private static ReviewResult pending(String... acknowledgementValues) {
        java.util.ArrayList<ReviewedDocument> acknowledgements = new java.util.ArrayList<>();
        for (int index = 0; index < acknowledgementValues.length; index += 2)
            acknowledgements.add(new ReviewedDocument(acknowledgementValues[index], acknowledgementValues[index + 1]));
        return new ReviewResult("DREV-00000000000000000000000000000000", "APP-ONE", "WF-ONE", "review_documents",
                ReviewStatus.ACK_PENDING, ReviewDisposition.MANUAL_REVIEW, "document-review-v1",
                new DocumentCounts(2, 0, 2, 0, 0), List.of(), "0123456789abcdef0123456789abcdef", acknowledgements);
    }

    private static ReviewResult completed() {
        return new ReviewResult("DREV-00000000000000000000000000000000", "APP-ONE", "WF-ONE", "review_documents",
                ReviewStatus.COMPLETED, ReviewDisposition.CLEAR, "document-review-v1",
                new DocumentCounts(1, 1, 0, 0, 0), List.of(), "0123456789abcdef0123456789abcdef", List.of());
    }
}
