// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentingest.service;

import com.cloudbank.documentingest.model.ReviewInputModels.ReviewInputResponse;
import com.cloudbank.documentingest.persistence.ExtractionRepository;
import org.springframework.stereotype.Service;

@Service
public class ReviewInputService {
    private final ExtractionRepository repository;
    public ReviewInputService(ExtractionRepository repository) {
        this.repository = repository;
    }

    public ReviewInputResponse reviewInput(String applicationId) {
        return new ReviewInputResponse(applicationId, repository.reviewInput(applicationId));
    }
}
