// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.api;

import com.cloudbank.loanapplication.api.ApplicationApiModels.ErrorResponse;
import com.cloudbank.loanapplication.api.ApplicationApiModels.FieldError;
import com.cloudbank.loanapplication.service.LoanServiceException;
import jakarta.validation.ConstraintViolationException;
import java.util.List;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.resource.NoResourceFoundException;

@RestControllerAdvice
public class ApiExceptionHandler {

    private static final Logger LOGGER = LoggerFactory.getLogger(ApiExceptionHandler.class);

    @ExceptionHandler(LoanServiceException.class)
    ResponseEntity<ErrorResponse> loanServiceException(LoanServiceException exception) {
        return ResponseEntity.status(exception.status()).body(error(exception.code(), exception.getMessage(),
                exception.retryable(), null, List.of()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<ErrorResponse> invalidBody(MethodArgumentNotValidException exception) {
        List<FieldError> fields = exception.getBindingResult().getFieldErrors().stream()
                .map(error -> new FieldError(error.getField(), error.getDefaultMessage()))
                .toList();
        return ResponseEntity.unprocessableContent().body(error("VALIDATION_FAILED",
                "The request contains invalid fields", false, null, fields));
    }

    @ExceptionHandler(ConstraintViolationException.class)
    ResponseEntity<ErrorResponse> invalidParameter(ConstraintViolationException exception) {
        List<FieldError> fields = exception.getConstraintViolations().stream()
                .map(error -> new FieldError(error.getPropertyPath().toString(), error.getMessage()))
                .toList();
        return ResponseEntity.unprocessableContent().body(error("VALIDATION_FAILED",
                "The request contains invalid parameters", false, null, fields));
    }

    @ExceptionHandler(DataIntegrityViolationException.class)
    ResponseEntity<ErrorResponse> integrityViolation(DataIntegrityViolationException exception) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(error("DATA_CONFLICT",
                "The request conflicts with existing application data", false, null, List.of()));
    }

    @ExceptionHandler(AccessDeniedException.class)
    ResponseEntity<ErrorResponse> accessDenied(AccessDeniedException exception) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(error("ACCESS_DENIED",
                "The requested operation is not permitted", false, "denied", List.of()));
    }

    @ExceptionHandler(NoResourceFoundException.class)
    ResponseEntity<ErrorResponse> resourceNotFound(NoResourceFoundException exception) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(error("RESOURCE_NOT_FOUND",
                "The requested resource was not found", false, null, List.of()));
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<ErrorResponse> unexpected(Exception exception) {
        String correlationId = UUID.randomUUID().toString();
        LOGGER.error("Unhandled request failure correlationId={}", correlationId, exception);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(new ErrorResponse(
                "INTERNAL_ERROR", "The request could not be completed", correlationId,
                true, null, List.of()));
    }

    private static ErrorResponse error(String code, String message, boolean retryable,
            String authorizationStatus, List<FieldError> fields) {
        return new ErrorResponse(code, message, UUID.randomUUID().toString(), retryable,
                authorizationStatus, fields);
    }
}
