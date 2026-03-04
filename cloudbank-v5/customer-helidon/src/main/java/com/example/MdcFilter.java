// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/
package com.example;

import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanContext;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.container.ContainerResponseContext;
import jakarta.ws.rs.container.ContainerResponseFilter;
import jakarta.ws.rs.ext.Provider;
import org.slf4j.MDC;
import java.io.IOException;

/**
 * A JAX-RS Container Filter that intercepts incoming HTTP requests and bridges
 * the active OpenTelemetry execution context into the SLF4J Mapped Diagnostic
 * Context(MDC).
 * <p>
 * This filter extracts the Trace ID, Span ID, and Trace Flags from the active
 * OTel Span and populates the SLF4J MDC map at the start of every HTTP request.
 * It strictly cleans up the MDC map during the HTTP response lifecycle phase to
 * prevent context-bleeding across concurrent virtual threads.
 */
@Provider
public class MdcFilter implements ContainerRequestFilter, ContainerResponseFilter {
    @Override
    public void filter(ContainerRequestContext requestContext) throws IOException {
        SpanContext spanContext = Span.current().getSpanContext();
        if (spanContext.isValid()) {
            MDC.put("trace_id", spanContext.getTraceId());
            MDC.put("span_id", spanContext.getSpanId());
            MDC.put("trace_flags", spanContext.getTraceFlags().asHex());
        }
    }

    @Override
    public void filter(ContainerRequestContext requestContext, ContainerResponseContext responseContext)
            throws IOException {
        MDC.remove("trace_id");
        MDC.remove("span_id");
        MDC.remove("trace_flags");
    }
}
