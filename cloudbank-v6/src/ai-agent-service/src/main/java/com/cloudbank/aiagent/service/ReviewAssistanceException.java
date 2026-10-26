// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.aiagent.service;

import org.springframework.http.HttpStatus;

public final class ReviewAssistanceException extends RuntimeException {
    private final String code;
    private final HttpStatus status;
    private final boolean retryable;

    private ReviewAssistanceException(String code, String message, HttpStatus status, boolean retryable,
            Throwable cause) {
        super(message, cause);
        this.code = code;
        this.status = status;
        this.retryable = retryable;
    }

    public static ReviewAssistanceException evidenceMismatch() {
        return new ReviewAssistanceException("REVIEW_EVIDENCE_MISMATCH",
                "Document-review evidence does not match the assistance request.", HttpStatus.CONFLICT, false, null);
    }

    public static ReviewAssistanceException downstreamUnavailable() {
        return downstreamUnavailable(null);
    }

    public static ReviewAssistanceException downstreamUnavailable(Throwable cause) {
        return new ReviewAssistanceException("DOCUMENT_REVIEW_UNAVAILABLE",
                "Document-review evidence is temporarily unavailable.", HttpStatus.BAD_GATEWAY, true, cause);
    }

    public static ReviewAssistanceException reviewNotFound() {
        return new ReviewAssistanceException("DOCUMENT_REVIEW_NOT_FOUND",
                "The referenced document review was not found.", HttpStatus.NOT_FOUND, false, null);
    }

    public static ReviewAssistanceException modelUnavailable(Throwable cause) {
        return new ReviewAssistanceException("GENAI_UNAVAILABLE",
                "OCI Generative AI review assistance is temporarily unavailable.", HttpStatus.SERVICE_UNAVAILABLE,
                true, cause);
    }

    public static ReviewAssistanceException unsafeModelOutput() {
        return new ReviewAssistanceException("GENAI_OUTPUT_REJECTED",
                "The generated review assistance did not pass output validation.", HttpStatus.BAD_GATEWAY, true,
                null);
    }

    public static ReviewAssistanceException extractionsUnavailable(Throwable cause) {
        return new ReviewAssistanceException("EXTRACTION_EVIDENCE_UNAVAILABLE",
                "Bounded extraction evidence is temporarily unavailable.", HttpStatus.BAD_GATEWAY, true, cause);
    }

    public static ReviewAssistanceException invalidEvidence() {
        return new ReviewAssistanceException("AI_EVIDENCE_REJECTED",
                "The evidence did not pass bounded input validation.", HttpStatus.CONFLICT, false, null);
    }

    public static ReviewAssistanceException idempotencyConflict() {
        return new ReviewAssistanceException("IDEMPOTENCY_CONFLICT",
                "The idempotency key is already bound to another summary request.", HttpStatus.CONFLICT, false, null);
    }

    public static ReviewAssistanceException resultStoreUnavailable(Throwable cause) {
        return new ReviewAssistanceException("AI_RESULT_STORE_UNAVAILABLE",
                "The durable AI result store is temporarily unavailable.", HttpStatus.SERVICE_UNAVAILABLE, true, cause);
    }

    public String code() {
        return code;
    }

    public HttpStatus status() {
        return status;
    }

    public boolean retryable() {
        return retryable;
    }
}
