// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.aiagent.client;

import java.util.List;

public record DocumentReviewEvidence(String reviewId, String applicationId, String workflowId,
        String taskReference, String reviewStatus, String disposition, String profileVersion,
        DocumentCounts documentCounts, List<ReviewIssue> issues, String traceId) {

    public record DocumentCounts(int total, int validated, int needsReview, int retryRequired, int blocked) {
    }

    public record ReviewIssue(String issueCode, String severity, String routingEffect, List<String> documentIds,
            String message) {
    }
}
