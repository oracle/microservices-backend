---
title: Configure Applications for SigNoz
sidebar_position: 6
---
## Configure Spring Boot applications for SigNoz Observability

In order for SigNoz to collect logs, metrics, and traces from applications, some configurations must be added.

:::note
 Looking for Helidon applications - see [below](#configure-helidon-applications-for-signoz-observability)
:::

### Configure OpenTelemetry and Micrometer

[OpenTelemetry zero-code instrumentation](https://opentelemetry.io/docs/zero-code/java/spring-boot-starter/getting-started/) enables adding observability to Spring Boot based applications without changing any code. Similarly [Micrometer](https://docs.micrometer.io/micrometer/reference/observation/projects.html) enables instrumentation of JVM based applications and can be configured using Spring Boot starters.

:::note
The versions in the below pom.xml might be outdated.
:::

```xml
<dependencies>
    <dependency>
        <groupId>io.micrometer</groupId>
        <artifactId>micrometer-core</artifactId>
    </dependency>
    <dependency>
        <groupId>io.micrometer</groupId>
        <artifactId>micrometer-registry-prometheus</artifactId>
    </dependency>
    <dependency>
        <groupId>io.micrometer</groupId>
        <artifactId>micrometer-tracing-bridge-otel</artifactId>
        <exclusions>
            <exclusion>
                <groupId>io.opentelemetry.instrumentation</groupId>
                <artifactId>opentelemetry-instrumentation-api-incubator</artifactId>
            </exclusion>
        </exclusions>
    </dependency>
    <dependency>
        <groupId>io.opentelemetry</groupId>
        <artifactId>opentelemetry-exporter-otlp</artifactId>
    </dependency>
    <dependency>
        <groupId>io.micrometer</groupId>
        <artifactId>micrometer-tracing</artifactId>
    </dependency>
    <dependency>
        <groupId>io.opentelemetry.instrumentation</groupId>
        <artifactId>opentelemetry-spring-boot-starter</artifactId>
    </dependency>
    <dependency>
        <groupId>net.ttddyy.observation</groupId>
        <artifactId>datasource-micrometer-spring-boot</artifactId>
    </dependency>
    <dependency>
        <groupId>com.oracle.database.spring</groupId>
        <artifactId>oracle-spring-boot-starter-ucp</artifactId>
        <type>pom</type>
    </dependency>
    <dependency>
        <groupId>io.opentelemetry.instrumentation</groupId>
        <artifactId>opentelemetry-oracle-ucp-11.2</artifactId>
    </dependency>
</dependencies>

<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>io.opentelemetry.instrumentation</groupId>
            <artifactId>opentelemetry-instrumentation-bom</artifactId>
            <type>pom</type>
            <scope>import</scope>
        </dependency>
        <dependency>
            <groupId>io.micrometer</groupId>
            <artifactId>micrometer-tracing-bom</artifactId>
            <version>${micrometer-tracing.version}</version>
            <type>pom</type>
            <scope>import</scope>
        </dependency>
    </dependencies>
</dependencyManagement>
```

### Configure Datasource Observability

[datasource-micrometer](https://github.com/jdbc-observations/datasource-micrometer) and [Oracle Universal Connection Pool Instrumentation](https://github.com/open-telemetry/opentelemetry-java-instrumentation/tree/main/instrumentation/oracle-ucp-11.2) can be configured to enable observability for Database connections and queries.

:::note
The versions in the below pom.xml might be outdated.
:::

```xml
<dependencies>
    <dependency>
        <groupId>net.ttddyy.observation</groupId>
        <artifactId>datasource-micrometer-spring-boot</artifactId>
    </dependency>
    <dependency>
        <groupId>io.opentelemetry.instrumentation</groupId>
        <artifactId>opentelemetry-oracle-ucp-11.2</artifactId>
    </dependency>
</dependencies>
```

### Configure Spring Boot Actuator

When you deploy an application with Oracle Backend for Microservices and AI CLI or Visual Code Extension, provided you included the Spring Actuator in your application, SigNoz will automatically find your application (using the annotations) and start collecting metrics. These metrics will be included in both the Spring Boot Observability dashboard and the Spring Boot Statistics dashboard automatically.

To include the Actuator in your application, add the following dependencies to your Maven POM or equivalent:

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
```

You must also add the configuration similar to one given below, after customizing it for your application, to your Spring `application.yaml`

```yaml
spring:
  threads:
    virtual:
      enabled: true
  jpa:
    hibernate:
      ddl-auto: validate
    properties:
      hibernate:
        dialect: org.hibernate.dialect.OracleDialect
        format_sql: true
    show-sql: true

eureka:
  instance:
    hostname: ${spring.application.name}
    preferIpAddress: true
  client:
    service-url:
      defaultZone: ${eureka.service-url}
    fetch-registry: true
    register-with-eureka: true
    enabled: true

management:
  endpoint:
    health:
      show-details: always
      show-components: always
  endpoints:
    web:
      exposure:
        include: "*"
  metrics:
    tags:
      application: ${spring.application.name}
    distribution:
      percentiles[http.server.requests]: 0.5, 0.90, 0.95, 0.99
      percentiles-histogram[http.server.requests]: true
      slo[http.server.requests]: 100ms, 250ms, 500ms, 1s, 2s, 5s, 10s, 30s
      percentiles[http.client.requests]: 0.5, 0.90, 0.95, 0.99
      percentiles-histogram[http.client.requests]: true
      slo[http.client.requests]: 100ms, 250ms, 500ms, 1s, 2s, 5s, 10s, 30s
  health:
    probes:
      enabled: true
  tracing:
    sampling:
      probability: 1.0
  info:
    os:
      enabled: true
    env:
      enabled: true
    java:
      enabled: true
  observations:
    key-values:
      app: ${spring.application.name}

logging:
  level:
    root: INFO
    com.example: INFO
    org.springframework.web.filter.AbstractRequestLoggingFilter: INFO

jdbc:
  datasource-proxy:
    query:
      enable-logging: true
      log-level: INFO
    include-parameter-values: true
```

The Oracle Backend for Microservices and AI platform adds the following annotations to your application pods for SigNoz to start scraping the actuator endpoint for metrics.

```yaml
signoz.io/path: /actuator/prometheus
signoz.io/port: "8080"
signoz.io/scrape: "true"
```

It also adds the `OTEL_EXPORTER_OTLP_ENDPOINT` to pod environment variables for the OpenTelemetry instrumentation libraries to access the OpenTelemetry collector of SigNoz.

:::note About the Service Name
`obaas` is the default Helm release name used when installing the SigNoz chart. The service name follows the pattern `<release-name>-signoz-otel-collector`. If you used a different release name during installation replace `<release-name>` with your release name:

:::tip Finding Your Namespace
If you deployed with Terraform, your namespace is typically your `label_prefix` value.
If you deployed with Helm, it's the namespace you specified during installation (e.g., `obaas-prod`, `tenant1`, etc.), referred to as `<namespace>` in the example below.
:::

```yaml
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: http://<release-name>-signoz-otel-collector.<namespace>:4318
```

## Configure Helidon applications for SigNoz Observability

In order for SigNoz to collect logs, metrics, and traces from Helidon applications, some configurations must be added.

### Configure OpenTelemetry

OpenTelemetry provides instrumentation without any code changes.  To enable OpenTelemetry, add these Helidon dependencies to your application's `pom.xml`:

```xml
<dependency>
    <groupId>io.helidon.microprofile.telemetry</groupId>
    <artifactId>helidon-microprofile-telemetry</artifactId>
</dependency>
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-exporter-otlp</artifactId>
</dependency>

```

Then, add the following configuration properties to your `microprofile-config.properties`. Replace `APP_NAME` with the name of your application:

```
metrics.rest-request.enabled=true
otel.sdk.disabled=false
otel.service.name=APP_NAME
otel.logs.exporter=otlp
otel.exporter.otlp.protocol=http/protobuf

# If you are using Helidon MP, you may change the following to true 
# to enable the optional MicroProfile Metrics REST.request metrics
metrics.rest-request.enabled=false
```

:::note
 When you deploy your Helidon applications with the OBaaS application Helm chart, it will automatically add the necessary enviornment variables
 to configure the endpoint addresses when you set `obaas.otel.enabled: true` in your `values.yaml`.
:::

### Structured Logging

We recommend that you configure your Helidon application to use Structured JSON logging, including trace correlation - which will allow you to easily
navigate between traces and the matching logs - without any manual OpenTelemetry SDK configuration.

First, add the following dependencies to your applications `pom.xml`:

```xml
<!-- Core Logging Frameworks (SLF4J API and Logback implementation) -->
<dependency>
    <groupId>org.slf4j</groupId>
    <artifactId>slf4j-api</artifactId>
    <version>2.0.9</version>
</dependency>
<dependency>
    <groupId>ch.qos.logback</groupId>
    <artifactId>logback-classic</artifactId>
    <version>1.4.14</version>
</dependency>
<!-- Bridge internal Helidon JUL logs to SLF4J/Logback -->
<dependency>
    <groupId>org.slf4j</groupId>
    <artifactId>jul-to-slf4j</artifactId>
    <version>2.0.9</version>
</dependency>
<!-- Structural JSON Logging -->
<dependency>
    <groupId>net.logstash.logback</groupId>
    <artifactId>logstash-logback-encoder</artifactId>
    <version>7.4</version>
</dependency>
<dependency>
    <groupId>io.opentelemetry.instrumentation</groupId>
    <artifactId>opentelemetry-logback-mdc-1.0</artifactId>
    <version>2.1.0-alpha</version> 
    <!-- Depending on OPENTELEMETRY java instrumentation version, usually 2.x or 1.x aligns with the SDK -->
    <scope>runtime</scope>
</dependency>
```

Next, create a configuration file for logging.  Create a file called `src/main/resources/logback.xml` with the following content.  This 
standardizes all container application text output to pure JSON string lines via the `LogstashEncoder`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <!-- 
      Console appender for structured JSON logs. 
      This leverages LogstashEncoder and MDC / OpenTelemetry provider auto-injection 
      so OpenTelemetry Agents can scrape contextually rich stdout logs.
    -->
    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder class="net.logstash.logback.encoder.LogstashEncoder" />
    </appender>

    <!--
      Configure the root logger to uniquely send logs to JSON Console.
    -->
    <root level="INFO">
        <appender-ref ref="CONSOLE" />
    </root>

    <!-- Quiet down verbose internal Helidon logs if necessary -->
    <logger name="org.jboss.weld" level="WARN" />
</configuration>
```

For trace injection, create a custom JAX-RS `ContainerRequestFilter` that intercepts incoming HTTP requests, extracts the
active `trace_id` and `span_id` from the OpenTelemetry `SpanContext`, and securely drops them into the SLF4J ThreadLocal MDC.

Create a new Java class in your application called `MdcFilter.java` with this content.  Update the Java package as necessary:

```java
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
import jakarta.annotation.Priority;
import jakarta.ws.rs.Priorities;
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
 * <p>
 * The @Priority annotation ensures this filter executes after Helidon's
 * internal OpenTelemetry filters have initialized the tracing span for the
 * incoming request, guaranteeing that Span.current() will return a valid
 * context.
 */
@Provider
@Priority(Priorities.USER + 100)
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
```

With this configuration, logs will be printed to stdout in pure JSON with trace IDs attached, and the cluster's
OpenTelemetry DaemonSet will natively scrape, parse, and correlate the logs entirely outside of the application's runtime.

With this approach:

* You do not need to configure a custom `GlobalOpenTelemetry` in your application.
* Any `LOGGER.info()` statement will get stamped with the distributed Trace ID.
* There is minimal overhead - your application only prints text locally; the cluster agent handles the expensive network gRPC telemetry export.