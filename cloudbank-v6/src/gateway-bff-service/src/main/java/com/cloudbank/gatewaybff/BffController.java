// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.gatewaybff;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import jakarta.servlet.http.Cookie;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.web.authentication.logout.SecurityContextLogoutHandler;
import org.springframework.security.web.csrf.CsrfToken;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.server.ResponseStatusException;

@RestController
class BffController {
    private final SessionIdentity identity;
    private final RestClient loan;

    BffController(SessionIdentity identity, @Value("${cloudbank.bff.loan-base-url}") String loanBaseUrl,
            RestClient.Builder restClientBuilder) {
        this.identity = identity;
        this.loan = restClientBuilder.baseUrl(loanBaseUrl).build();
    }

    @GetMapping("/bff/auth/login")
    ResponseEntity<Void> login() {
        return ResponseEntity.status(HttpStatus.FOUND)
                .header(HttpHeaders.LOCATION, "/oauth2/authorization/" + BffSecurityConfig.REGISTRATION_ID)
                .build();
    }

    @PostMapping("/bff/auth/logout")
    ResponseEntity<Void> logout(Authentication authentication, HttpServletRequest request,
            HttpServletResponse response) {
        identity.require(authentication, request);
        new SecurityContextLogoutHandler().logout(request, response, authentication);
        Cookie cookie = new Cookie("CBBFFSESSION", "");
        cookie.setPath("/");
        cookie.setHttpOnly(true);
        cookie.setSecure(request.isSecure());
        cookie.setMaxAge(0);
        cookie.setAttribute("SameSite", "Lax");
        response.addCookie(cookie);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/bff/api/v1/session")
    SessionResponse session(Authentication authentication, HttpServletRequest request) {
        SessionIdentity.AuthorizedUser user = identity.require(authentication, request);
        HttpSession session = request.getSession(false);
        if (session == null) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Session expired");
        }
        CsrfToken csrf = (CsrfToken) request.getAttribute(CsrfToken.class.getName());
        if (csrf == null) {
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "CSRF unavailable");
        }
        Instant expiresAt = Instant.ofEpochMilli(session.getLastAccessedTime())
                .plusSeconds(session.getMaxInactiveInterval());
        if (user.tokenExpiresAt() != null && user.tokenExpiresAt().isBefore(expiresAt)) {
            expiresAt = user.tokenExpiresAt();
        }
        return new SessionResponse(true, new User("OBaaS Admin", user.username()), "obaas-admin",
                expiresAt, "api", csrf.getHeaderName(), csrf.getToken());
    }

    @GetMapping("/bff/api/v1/applications")
    ApplicationPage applications(@RequestParam(required = false) String status,
            @RequestParam(required = false) String scenarioId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            Authentication authentication, HttpServletRequest request) {
        String accessToken = identity.require(authentication, request).accessToken();
        try {
            LoanPage upstream = loan.get()
                    .uri(uri -> {
                        uri.path("/api/v1/loan-applications").queryParam("page", page).queryParam("size", size);
                        if (status != null && !status.isBlank()) {
                            uri.queryParam("status", status);
                        }
                        if (scenarioId != null && !scenarioId.isBlank()) {
                            uri.queryParam("scenarioId", scenarioId);
                        }
                        return uri.build();
                    })
                    .headers(headers -> headers.setBearerAuth(accessToken))
                    .retrieve().body(LoanPage.class);
            if (upstream == null || upstream.content() == null || upstream.page() == null) {
                throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Loan response unavailable");
            }
            return new ApplicationPage(upstream.content().stream().map(row -> new ApplicationItem(
                    row.applicationId(), row.scenarioId(), row.scenarioName(), row.status(),
                    row.requestedAmount(), row.requestedTermMonths(), row.createdAt(), row.updatedAt(),
                    row.workflow() == null ? null : row.workflow().workflowId(), row.traceId())).toList(),
                    upstream.page());
        } catch (RestClientResponseException upstream) {
            HttpStatus statusCode = switch (upstream.getStatusCode().value()) {
                case 400 -> HttpStatus.BAD_REQUEST;
                case 401 -> HttpStatus.BAD_GATEWAY;
                case 403 -> HttpStatus.FORBIDDEN;
                case 503 -> HttpStatus.SERVICE_UNAVAILABLE;
                default -> HttpStatus.BAD_GATEWAY;
            };
            throw new ResponseStatusException(statusCode, "Loan service request failed");
        } catch (RestClientException upstream) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Loan service unavailable");
        }
    }

    record User(String displayName, String username) {
    }

    record SessionResponse(boolean authenticated, User user, String profile, Instant expiresAt,
            String dataMode, String csrfHeaderName, String csrfToken) {
    }

    record ApplicationPage(List<ApplicationItem> content, PageMetadata page) {
    }

    record ApplicationItem(String applicationId, String scenarioId, String scenarioName, String status,
            BigDecimal requestedAmount, Integer requestedTermMonths, Instant createdAt, Instant updatedAt,
            String workflowId, String traceId) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    record LoanPage(List<LoanItem> content, PageMetadata page) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    record LoanItem(String applicationId, String scenarioId, String scenarioName, String status,
            BigDecimal requestedAmount, Integer requestedTermMonths, Instant createdAt, Instant updatedAt,
            Workflow workflow, String traceId) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    record Workflow(String workflowId) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    record PageMetadata(int number, int size, long totalElements, long totalPages) {
    }
}
