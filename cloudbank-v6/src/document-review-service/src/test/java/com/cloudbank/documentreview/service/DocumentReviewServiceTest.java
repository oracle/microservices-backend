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
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.cloudbank.documentreview.api.DocumentReviewApiModels.DocumentReviewRequest;
import com.cloudbank.documentreview.client.DocumentIngestClient;
import com.cloudbank.documentreview.client.LoanApplicationClient;
import com.cloudbank.documentreview.domain.ReviewModels.DocumentCounts;
import com.cloudbank.documentreview.domain.ReviewModels.DocumentManifest;
import com.cloudbank.documentreview.domain.ReviewModels.ExtractionReviewInput;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewDisposition;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewResult;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewStatus;
import com.cloudbank.documentreview.domain.ReviewModels.StoredReview;
import com.cloudbank.documentreview.persistence.DocumentReviewRepository;
import com.cloudbank.documentreview.rules.DocumentReviewV2Profile;
import java.util.List;
import java.util.Optional;
import java.util.function.Supplier;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import tools.jackson.databind.ObjectMapper;

@ExtendWith(MockitoExtension.class)
class DocumentReviewServiceTest {
    @Mock
    private LoanApplicationClient loan;
    @Mock
    private DocumentIngestClient ingest;
    @Mock
    private DocumentReviewRepository repository;
    @Mock
    private DocumentReviewV2Profile profile;
    @Mock
    private ReviewFingerprintService fingerprints;
    @Mock
    private DocumentReviewPersistenceService persistence;
    @Mock
    private DocumentStatusAcknowledgementService acknowledgements;

    private DocumentReviewService service;

    @BeforeEach
    void setUp() {
        service = new DocumentReviewService(loan, ingest, repository, profile, fingerprints, persistence,
                acknowledgements,
                new ObjectMapper());
    }

    @Test
    void completedIdempotentRequestReturnsTheStoredResultWithoutCallingDependencies() {
        ReviewResult result = completed();
        when(fingerprints.sha256(anyString())).thenReturn("hash");
        when(repository.findByIdempotencyHash("hash")).thenReturn(Optional.of(new StoredReview(result, "hash")));

        assertThat(service.review(request(), "key-12345")).isSameAs(result);

        verify(loan, never()).manifest(anyString());
        verify(ingest, never()).reviewInput(anyString());
        verify(acknowledgements, never()).acknowledge(any(), any());
    }

    @Test
    void reusingAnIdempotencyKeyForDifferentContentIsRejected() {
        when(fingerprints.sha256("key-12345")).thenReturn("idempotency-hash");
        when(repository.findByIdempotencyHash("idempotency-hash"))
                .thenReturn(Optional.of(new StoredReview(completed(), "different-request-hash")));

        assertThatThrownBy(() -> service.review(request(), "key-12345")).isInstanceOf(ReviewServiceException.class)
                .satisfies(exception -> {
                    ReviewServiceException review = (ReviewServiceException) exception;
                    assertThat(review.code()).isEqualTo("IDEMPOTENCY_KEY_CONFLICT");
                    assertThat(review.status()).isEqualTo(HttpStatus.CONFLICT);
                });
    }

    @Test
    void firstRequestPersistsTheReviewAndAcknowledgesIt() {
        DocumentManifest manifest = new DocumentManifest("APP-ONE", List.of());
        ExtractionReviewInput input = new ExtractionReviewInput("APP-ONE", List.of());
        ReviewResult pending = pending();
        ReviewResult complete = completed();
        when(fingerprints.sha256(anyString())).thenReturn("hash");
        when(fingerprints.reviewId(anyString(), anyString(), anyString())).thenReturn(pending.reviewId());
        when(repository.findByIdempotencyHash("hash")).thenReturn(Optional.empty());
        when(loan.manifest("APP-ONE")).thenReturn(manifest);
        when(ingest.reviewInput("APP-ONE")).thenReturn(input);
        when(profile.evaluate(anyString(), anyString(), anyString(), anyString(), anyString(), any(), any()))
                .thenReturn(pending);
        when(acknowledgements.acknowledge(pending, manifest)).thenReturn(complete);

        assertThat(service.review(request(), "key-12345")).isSameAs(complete);

        verify(persistence).persistPending(any(), any(), anyString(), anyString(), anyString());
        verify(acknowledgements).acknowledge(pending, manifest);
    }

    @Test
    void missingUpstreamContractIsReportedAsBadGateway() {
        when(fingerprints.sha256(anyString())).thenReturn("hash");
        when(repository.findByIdempotencyHash("hash")).thenReturn(Optional.empty());
        when(loan.manifest("APP-ONE")).thenReturn(null);

        assertThatThrownBy(() -> service.review(request(), "key-12345")).isInstanceOf(ReviewServiceException.class)
                .satisfies(exception -> {
                    ReviewServiceException review = (ReviewServiceException) exception;
                    assertThat(review.code()).isEqualTo("DOCUMENT_MANIFEST_INVALID");
                    assertThat(review.status()).isEqualTo(HttpStatus.BAD_GATEWAY);
                });
    }

    @Test
    void mismatchedApplicationContextFailsBeforeReviewOrPersistence() {
        when(fingerprints.sha256(anyString())).thenReturn("hash");
        when(repository.findByIdempotencyHash("hash")).thenReturn(Optional.empty());
        when(loan.manifest("APP-ONE")).thenReturn(new DocumentManifest("APP-ONE", List.of()));
        when(ingest.reviewInput("APP-ONE")).thenReturn(new ExtractionReviewInput("APP-OTHER", List.of()));
        assertThatThrownBy(() -> service.review(request(), "key-12345"))
                .isInstanceOfSatisfying(ReviewServiceException.class,
                        error -> assertThat(error.code()).isEqualTo("APPLICATION_CONTEXT_MISMATCH"));
        verify(profile, never()).evaluate(anyString(), anyString(), anyString(), anyString(), anyString(), any(), any());
        verify(persistence, never()).persistPending(any(), any(), anyString(), anyString(), anyString());
    }

    private static Supplier<?> anySupplier() {
        return any();
    }

    private static DocumentReviewRequest request() {
        return new DocumentReviewRequest("APP-ONE", "WF-ONE", "review_documents", "0123456789abcdef0123456789abcdef");
    }

    private static ReviewResult pending() {
        return result(ReviewStatus.ACK_PENDING);
    }

    private static ReviewResult completed() {
        return result(ReviewStatus.COMPLETED);
    }

    private static ReviewResult result(ReviewStatus status) {
        return new ReviewResult("DREV-00000000000000000000000000000000", "APP-ONE", "WF-ONE", "review_documents",
                status, ReviewDisposition.CLEAR, "document-review-v1", new DocumentCounts(0, 0, 0, 0, 0), List.of(),
                "0123456789abcdef0123456789abcdef", List.of());
    }
}
