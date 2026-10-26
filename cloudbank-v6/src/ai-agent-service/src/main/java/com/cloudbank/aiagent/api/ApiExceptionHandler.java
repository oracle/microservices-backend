// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.aiagent.api;

import com.cloudbank.aiagent.api.AiAgentApiModels.ErrorResponse;
import com.cloudbank.aiagent.service.ReviewAssistanceException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.ConstraintViolationException;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.resource.NoResourceFoundException;

@RestControllerAdvice
public class ApiExceptionHandler {
    @ExceptionHandler({ MethodArgumentNotValidException.class, ConstraintViolationException.class })
    ResponseEntity<ErrorResponse> validation(Exception exception, HttpServletRequest request) {
        return ResponseEntity.badRequest()
                .body(error("VALIDATION_FAILED", "Request validation failed.", request, false));
    }

    @ExceptionHandler(AccessDeniedException.class)
    ResponseEntity<ErrorResponse> forbidden(AccessDeniedException exception, HttpServletRequest request) {
        return ResponseEntity.status(403)
                .body(error("ACCESS_DENIED", "The caller is not authorized for this resource.", request, false));
    }

    @ExceptionHandler(NoResourceFoundException.class)
    ResponseEntity<ErrorResponse> notFound(NoResourceFoundException exception, HttpServletRequest request) {
        return ResponseEntity.status(404)
                .body(error("RESOURCE_NOT_FOUND", "The requested AI resource was not found.", request, false));
    }

    @ExceptionHandler(ReviewAssistanceException.class)
    ResponseEntity<ErrorResponse> reviewAssistance(ReviewAssistanceException exception, HttpServletRequest request) {
        return ResponseEntity.status(exception.status())
                .body(error(exception.code(), exception.getMessage(), request, exception.retryable()));
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<ErrorResponse> unexpected(Exception exception, HttpServletRequest request) {
        return ResponseEntity.internalServerError()
                .body(error("AI_AGENT_FAILURE", "The AI task result could not be created.", request, false));
    }

    private ErrorResponse error(String code, String message, HttpServletRequest request, boolean retryable) {
        String traceId = request.getHeader("X-Trace-Id");
        return new ErrorResponse(code, message, traceId == null ? "" : traceId, retryable);
    }
}
