// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.decision.api;

import com.cloudbank.decision.api.DecisionApiModels.ErrorResponse;
import com.cloudbank.decision.api.DecisionApiModels.FieldError;
import com.cloudbank.decision.service.DecisionServiceException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.ConstraintViolationException;
import java.util.Comparator;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class ApiExceptionHandler {
    private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);

    @ExceptionHandler(DecisionServiceException.class)
    ResponseEntity<ErrorResponse> decision(DecisionServiceException exception, HttpServletRequest request) {
        return ResponseEntity.status(exception.status())
                .body(error(exception.code(), exception.getMessage(), request, exception.retryable(), List.of()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<ErrorResponse> validation(MethodArgumentNotValidException exception, HttpServletRequest request) {
        List<FieldError> fields = exception.getBindingResult().getFieldErrors().stream()
                .map(field -> new FieldError(field.getField(), message(field.getDefaultMessage())))
                .distinct()
                .sorted(Comparator.comparing(FieldError::field).thenComparing(FieldError::message))
                .toList();
        return ResponseEntity.badRequest()
                .body(error("VALIDATION_FAILED", "Request validation failed.", request, false, fields));
    }

    @ExceptionHandler(ConstraintViolationException.class)
    ResponseEntity<ErrorResponse> validation(ConstraintViolationException exception, HttpServletRequest request) {
        List<FieldError> fields = exception.getConstraintViolations().stream()
                .map(violation -> new FieldError(violation.getPropertyPath().toString(),
                        message(violation.getMessage())))
                .distinct()
                .sorted(Comparator.comparing(FieldError::field).thenComparing(FieldError::message))
                .toList();
        return ResponseEntity.badRequest()
                .body(error("VALIDATION_FAILED", "Request validation failed.", request, false, fields));
    }

    @ExceptionHandler(AccessDeniedException.class)
    ResponseEntity<ErrorResponse> forbidden(AccessDeniedException exception, HttpServletRequest request) {
        return ResponseEntity.status(403).body(
                error("ACCESS_DENIED", "The caller is not authorized for this resource.", request, false, List.of()));
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<ErrorResponse> unexpected(Exception exception, HttpServletRequest request) {
        log.error("Deterministic decision failed correlationId={}", correlationId(request), exception);
        return ResponseEntity.internalServerError().body(error("DECISION_FAILURE",
                "Deterministic decision could not be completed.", request, true, List.of()));
    }

    private ErrorResponse error(String code, String message, HttpServletRequest request, boolean retryable,
            List<FieldError> fields) {
        return new ErrorResponse(code, message, correlationId(request), retryable, "AUTHORIZED", fields);
    }

    private String correlationId(HttpServletRequest request) {
        String trace = request.getHeader("X-Trace-Id");
        return trace == null ? "" : trace;
    }

    private String message(String validationMessage) {
        return validationMessage == null || validationMessage.isBlank() ? "invalid value" : validationMessage;
    }
}
