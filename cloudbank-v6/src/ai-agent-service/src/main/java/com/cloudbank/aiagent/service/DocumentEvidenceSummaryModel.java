// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.aiagent.service;

import java.util.List;

public interface DocumentEvidenceSummaryModel {
    DocumentSummaryModelOutput generate(String evidenceJson);

    record DocumentSummaryModelOutput(String summary, List<String> reviewNotes, List<String> evidenceDocumentIds) {
    }
}
