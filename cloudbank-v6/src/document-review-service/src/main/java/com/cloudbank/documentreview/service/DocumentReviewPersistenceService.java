// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentreview.service;

import com.cloudbank.documentreview.domain.ReviewModels.ExtractionReviewInput;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewResult;
import com.cloudbank.documentreview.persistence.DocumentReviewRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DocumentReviewPersistenceService {
    private final DocumentReviewRepository repository;

    public DocumentReviewPersistenceService(DocumentReviewRepository repository) {
        this.repository = repository;
    }

    @Transactional
    public void persistPending(ReviewResult result, ExtractionReviewInput input, String idempotencyHash,
            String requestHash, String inputFingerprint) {
        repository.persist(result, idempotencyHash, requestHash, inputFingerprint);
        repository.persistProjections(result, input);
    }
}
