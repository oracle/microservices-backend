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
 * the active
 * OpenTelemetry execution context into the SLF4J Mapped Diagnostic Context
 * (MDC).
 * <p>
 * Why is this necessary?
 * Standard Java/Helidon loggers rely on ThreadLocal variables (MDC) to attach
 * context to logs.
 * OpenTelemetry tracks distributed traces using its own context mechanism.
 * Without this bridge,
 * when the application logs a message, the logger has no idea what the current
 * Trace ID is.
 * <p>
 * This filter extracts the Trace ID, Span ID, and Trace Flags from the active
 * OTel Span
 * and actively populates the SLF4J MDC map at the start of every HTTP request.
 * It then
 * rigorously cleans up the MDC map on the HTTP response (in a `finally`
 * block-equivalent
 * lifecycle phase) to prevent catastrophic context-bleeding across Helidon
 * virtual threads.
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
