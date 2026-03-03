---
title: Configure Applications for SigNoz
sidebar_position: 5
---
## Configure applications for SigNoz Observability

In order for SigNoz to collect logs, metrics, and traces from applications, some configurations must be added.

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
