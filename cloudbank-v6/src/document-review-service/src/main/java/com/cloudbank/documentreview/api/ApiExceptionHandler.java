// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentreview.api;

import com.cloudbank.documentreview.api.DocumentReviewApiModels.ErrorResponse;
import com.cloudbank.documentreview.api.DocumentReviewApiModels.FieldError;
import com.cloudbank.documentreview.service.ReviewServiceException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.ConstraintViolationException;
import java.util.List;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class ApiExceptionHandler {
    @ExceptionHandler(ReviewServiceException.class)
    ResponseEntity<ErrorResponse> review(ReviewServiceException exception, HttpServletRequest request) {
        return ResponseEntity.status(exception.status())
                .body(error(exception.code(), exception.getMessage(), request, exception.retryable(), List.of()));
    }

    @ExceptionHandler({ MethodArgumentNotValidException.class, ConstraintViolationException.class })
    ResponseEntity<ErrorResponse> validation(Exception exception, HttpServletRequest request) {
        return ResponseEntity.badRequest()
                .body(error("VALIDATION_FAILED", "Request validation failed.", request, false, List.of()));
    }

    @ExceptionHandler(AccessDeniedException.class)
    ResponseEntity<ErrorResponse> forbidden(AccessDeniedException exception, HttpServletRequest request) {
        return ResponseEntity.status(403).body(
                error("ACCESS_DENIED", "The caller is not authorized for this resource.", request, false, List.of()));
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<ErrorResponse> unexpected(Exception exception, HttpServletRequest request) {
        return ResponseEntity.internalServerError().body(
                error("DOCUMENT_REVIEW_FAILURE", "Document review could not be completed.", request, false, List.of()));
    }

    private ErrorResponse error(String code, String message, HttpServletRequest request, boolean retryable,
            List<FieldError> fields) {
        String trace = request.getHeader("X-Trace-Id");
        return new ErrorResponse(code, message, trace == null ? "" : trace, retryable, "AUTHORIZED", fields);
    }
}
