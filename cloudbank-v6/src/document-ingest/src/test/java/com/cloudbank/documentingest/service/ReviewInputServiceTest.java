// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentingest.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.cloudbank.documentingest.model.ReviewInputModels.ReviewInputDocument;
import com.cloudbank.documentingest.persistence.ExtractionRepository;
import java.util.List;
import org.junit.jupiter.api.Test;

class ReviewInputServiceTest {

    @Test
    void readsReviewInput() {
        ExtractionRepository repository = mock(ExtractionRepository.class);
        ReviewInputService service = new ReviewInputService(repository);
        List<ReviewInputDocument> documents = List.of(new ReviewInputDocument("DOC-1", "LOAN_APPLICATION",
                "EXT-DOC-1", "SUCCEEDED", "DOCUMENT_INGEST", "local_pdf_text", null, null, List.of(), List.of()));
        when(repository.reviewInput("APP-TEST")).thenReturn(documents);
        var response = service.reviewInput("APP-TEST");

        assertThat(response.applicationId()).isEqualTo("APP-TEST");
        assertThat(response.documents()).containsExactlyElementsOf(documents);
        verify(repository).reviewInput("APP-TEST");
    }
}
