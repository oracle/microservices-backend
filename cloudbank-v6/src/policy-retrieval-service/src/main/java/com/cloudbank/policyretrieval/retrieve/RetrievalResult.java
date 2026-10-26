// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyretrieval.retrieve;

import com.cloudbank.policyretrieval.model.PolicyChunk;
import com.cloudbank.policyretrieval.model.PolicyDocument;

public record RetrievalResult(
        double vectorScore,
        PolicyChunk chunk,
        PolicyDocument document) {
}
