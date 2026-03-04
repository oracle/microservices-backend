package com.example;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.context.Initialized;
import jakarta.enterprise.event.Observes;
import jakarta.ws.rs.ApplicationPath;
import jakarta.ws.rs.core.Application;
import org.slf4j.bridge.SLF4JBridgeHandler;

import java.util.Set;

/**
 * JAX-RS Application configuration.
 * Installs the JUL-to-SLF4J bridge on startup so internal Helidon logs
 * are correctly routed to Logback.
 */
@ApplicationScoped
@ApplicationPath("/")
public class CustomerApplication extends Application {

    // We remove the injected OpenTelemetry instance because Helidon MicroProfile
    // Telemetry only fully initializes Traces and Metrics providers.
    // Instead, we will force the OpenTelemetry Auto-Configure SDK to initialize the
    // Logs.

    public void init(@Observes @Initialized(ApplicationScoped.class) Object event) {
        // Remove existing JUL handlers
        SLF4JBridgeHandler.removeHandlersForRootLogger();

        // Install the SLF4J Bridge Handler
        SLF4JBridgeHandler.install();

        System.out.println("Initialized SLF4JBridgeHandler to route Java Util Logging to Logback.");

        // We must initialize the AutoConfigured SDK to read the OTEL_* environment
        // variables
        // and physically boot up the OtlpHttpLogRecordExporter, since Helidon MP
        // Telemetry limits itself to Traces.
        // OTLP Log Exports will natively bypass the application since Kubernetes
        // OpenTelemetry Agents
        // scrape structural stdout Logs!
    }

    @Override
    public Set<Class<?>> getClasses() {
        return Set.of(CustomerResource.class, MdcFilter.class);
    }
}
