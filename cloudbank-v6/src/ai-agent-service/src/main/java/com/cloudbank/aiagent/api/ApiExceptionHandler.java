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
import org.springframework.web.server.ResponseStatusException;

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

    @ExceptionHandler(ResponseStatusException.class)
    ResponseEntity<ErrorResponse> responseStatus(ResponseStatusException exception, HttpServletRequest request) {
        // Workspace reads use 404 for absent/cross-workflow results. Preserve the
        // status instead of converting it into a generic task-creation failure.
        int status = exception.getStatusCode().value();
        String code = switch (status) {
            case 400 -> "INVALID_REQUEST";
            case 403 -> "ACCESS_DENIED";
            case 404 -> "AI_RESULT_UNAVAILABLE";
            case 502 -> "AI_RESULT_READ_FAILED";
            case 503 -> "AI_RESULT_STORE_UNAVAILABLE";
            default -> "AI_REQUEST_FAILED";
        };
        String message = status == 404 ? "The requested AI result is not available."
                : "The AI result could not be read.";
        return ResponseEntity.status(exception.getStatusCode())
                .header("Cache-Control", "private, no-store")
                .body(error(code, message, request, status == 503 || status == 504));
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<ErrorResponse> unexpected(Exception exception, HttpServletRequest request) {
        return ResponseEntity.internalServerError()
                .body(error("AI_AGENT_FAILURE", "The AI request could not be completed.", request, false));
    }

    private ErrorResponse error(String code, String message, HttpServletRequest request, boolean retryable) {
        String traceId = request.getHeader("X-Trace-Id");
        return new ErrorResponse(code, message, traceId == null ? "" : traceId, retryable);
    }
}
