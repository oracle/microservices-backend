// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.decision.service;

import org.springframework.http.HttpStatus;

public final class DecisionServiceException extends RuntimeException {
    private final String code;
    private final HttpStatus status;
    private final boolean retryable;

    public DecisionServiceException(String code, HttpStatus status, String message, boolean retryable) {
        super(message);
        this.code = code;
        this.status = status;
        this.retryable = retryable;
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
