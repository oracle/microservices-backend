// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.gatewaybff;

import jakarta.servlet.http.HttpServletRequest;
import java.io.IOException;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MissingRequestHeaderException;
import org.springframework.web.HttpMediaTypeNotSupportedException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.server.ResponseStatusException;

@RestControllerAdvice
class BffErrorHandler {
    @ExceptionHandler(ResponseStatusException.class)
    ResponseEntity<ErrorBody> handle(ResponseStatusException error, HttpServletRequest request) {
        int status = error.getStatusCode().value();
        return response(status, request);
    }

    @ExceptionHandler({HttpMessageNotReadableException.class, MissingRequestHeaderException.class})
    ResponseEntity<ErrorBody> malformed(Exception error, HttpServletRequest request) {
        return response(400, request);
    }

    @ExceptionHandler(HttpMediaTypeNotSupportedException.class)
    ResponseEntity<ErrorBody> unsupported(HttpMediaTypeNotSupportedException error, HttpServletRequest request) {
        return response(415, request);
    }

    @ExceptionHandler(IOException.class)
    ResponseEntity<ErrorBody> interruptedContent(IOException error, HttpServletRequest request) {
        return response(503, request);
    }

    private ResponseEntity<ErrorBody> response(int status, HttpServletRequest request) {
        boolean retryable = status == 502 || status == 503 || status == 504;
        String authorization = status == 401 ? "UNAUTHENTICATED" : status == 403 ? "DENIED" : "AUTHENTICATED";
        boolean upload = request.getRequestURI().endsWith("/content");
        boolean start = request.getRequestURI().endsWith("/workflow-start");
        boolean review = request.getRequestURI().contains("/manual-review/tasks");
        String code = switch (status) {
            case 400 -> "BAD_REQUEST";
            case 401 -> "UNAUTHENTICATED";
            case 403 -> "FORBIDDEN";
            case 404 -> "NOT_FOUND";
            case 409 -> "CONFLICT";
            case 413 -> "DOCUMENT_SIZE_INVALID";
            case 415 -> "UNSUPPORTED_MEDIA_TYPE";
            case 422 -> "REQUEST_REJECTED";
            case 503 -> "SERVICE_UNAVAILABLE";
            default -> "UPSTREAM_ERROR";
        };
        String message = switch (status) {
            case 400 -> review ? "Choose APPROVED or REJECTED, provide a reason code (3–120 uppercase letters, digits, _, : or -) and a policy section such as CBPL-150-S4." : "Invalid request";
            case 401 -> "Sign in required";
            case 403 -> review ? "Manual-review access denied. Completion requires an explicit UNDERWRITER grant and write scope." : "Access denied";
            case 404 -> review ? "Human task not found in your authorized scope" : "Application or document not found in your authorized scope";
            case 409 -> review ? "The task state or resolution has changed. Refresh the queue before submitting another outcome."
                    : upload ? "The document cannot be replaced or its upload state has changed. Retry with the original file."
                    : start ? "Processing cannot be started in the current application state."
                    : "This request conflicts with an existing operation. Check the application list before retrying.";
            case 413 -> "PDF content must contain between 1 byte and 25 MiB";
            case 415 -> upload ? "Document content must be sent as application/pdf" : "Send application metadata as JSON";
            case 422 -> "Application metadata was rejected. Review the entered details and document metadata.";
            default -> "Service temporarily unavailable";
        };
        String correlationId = (String) request.getAttribute("bffCorrelationId");
        return ResponseEntity.status(status).header("Cache-Control", "no-store")
                .body(new ErrorBody(code, message, correlationId, retryable, authorization));
    }

    record ErrorBody(String code, String message, String correlationId, boolean retryable,
            String authorizationStatus) {
    }
}
