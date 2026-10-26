// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.aznserver.securityconfig;

import java.io.IOException;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletRequestWrapper;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Retains a legacy MicroTx-compatible alias for standard OIDC endpoints.
 *
 * <p>The current OKE procedure uses the bare issuer and its discovery metadata.
 * This narrow alias remains available for existing deployments:
 * {@code GET /microtx/oidc/.well-known/openid-configuration} uses normal discovery and
 * {@code POST /microtx/oidc} uses the normal token endpoint.</p>
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class MicroTxOidcCompatibilityFilter extends OncePerRequestFilter {

    private static final String ALIAS = "/microtx/oidc";
    private static final String DISCOVERY_ALIAS = ALIAS + "/.well-known/openid-configuration";

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getRequestURI();
        return !("POST".equalsIgnoreCase(request.getMethod()) && ALIAS.equals(path))
                && !("GET".equalsIgnoreCase(request.getMethod()) && DISCOVERY_ALIAS.equals(path));
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        String targetPath = "POST".equalsIgnoreCase(request.getMethod()) ? "/oauth2/token"
                : "/.well-known/openid-configuration";
        filterChain.doFilter(new EndpointAliasRequest(request, targetPath), response);
    }

    private static final class EndpointAliasRequest extends HttpServletRequestWrapper {

        private final String targetPath;

        private EndpointAliasRequest(HttpServletRequest request, String targetPath) {
            super(request);
            this.targetPath = targetPath;
        }

        @Override
        public String getRequestURI() {
            return getContextPath() + targetPath;
        }

        @Override
        public String getServletPath() {
            return targetPath;
        }
    }
}
