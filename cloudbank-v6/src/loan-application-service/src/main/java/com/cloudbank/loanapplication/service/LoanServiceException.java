// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.service;

import org.springframework.http.HttpStatus;

public class LoanServiceException extends RuntimeException {

    private final String code;
    private final HttpStatus status;
    private final boolean retryable;

    public LoanServiceException(String code, HttpStatus status, String message) {
        this(code, status, message, false);
    }

    public LoanServiceException(String code, HttpStatus status, String message, boolean retryable) {
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
