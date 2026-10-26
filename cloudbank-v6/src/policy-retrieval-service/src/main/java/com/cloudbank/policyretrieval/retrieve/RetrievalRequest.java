// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyretrieval.retrieve;

import com.cloudbank.policyretrieval.model.AiUse;
import com.cloudbank.policyretrieval.model.PolicyRole;

public record RetrievalRequest(
        String content,
        float[] embedding,
        AiUse aiUse,
        PolicyRole policyRole
) {
}
