// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.
package com.cloudbank.gatewaybff;

import com.cloudbank.gatewaybff.ApplicationWorkspaceController.Section;
import com.cloudbank.gatewaybff.WorkspaceReadModels.Trace;
import com.cloudbank.gatewaybff.WorkspaceReadModels.TraceSpan;
import com.cloudbank.gatewaybff.WorkspaceReadModels.TraceSpans;
import java.math.BigDecimal;
import java.net.URI;
import java.net.http.HttpClient;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

/** Only called after the loan owner has authorized the selected application. */
@Service
class TraceReadService {
    private static final int MAX_BYTES = 2 * 1024 * 1024;
    private static final Set<String> SERVICES = Set.of("loan-application-service", "document-ingest",
            "document-review-service", "ai-agent-service", "decision-service", "geographic-risk-service",
            "policy-retrieval-service", "workflow-token-refresh-worker", "gateway-bff-service", "azn-server",
            "workflow-server", "microtx-workflow-server");
    private static final Set<String> METHODS = Set.of("GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS");
    private static final Set<String> DB_OPERATIONS = Set.of("SELECT", "INSERT", "UPDATE", "DELETE", "COMMIT",
            "ROLLBACK", "CALL", "EXECUTE");
    private final RestClient client;
    private final ObjectMapper json;
    private final String apiKey;
    private final String publicUrl;

    TraceReadService(RestClient.Builder builder, ObjectMapper json,
            @Value("${cloudbank.bff.signoz.base-url:}") String baseUrl,
            @Value("${cloudbank.bff.signoz.api-key:}") String apiKey,
            @Value("${cloudbank.bff.signoz.public-url:}") String publicUrl) {
        this.json = json;
        this.apiKey = apiKey;
        this.publicUrl = endpoint(publicUrl);
        String base = endpoint(baseUrl);
        var factory = new JdkClientHttpRequestFactory(HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(3)).followRedirects(HttpClient.Redirect.NEVER).build());
        factory.setReadTimeout(Duration.ofSeconds(8));
        this.client = base == null ? null : builder.clone().requestFactory(factory).baseUrl(base).build();
    }

    Section<Trace> compose(String applicationId, String workflowId, String ownerTraceId) {
        // IDs come from the authorized owner snapshot, never from a browser trace query.
        if (workflowId != null && !workflowId.matches("[A-Za-z0-9._:-]{1,100}")) return Section.error();
        String traceId = ownerTraceId != null && ownerTraceId.matches("[0-9a-fA-F]{32}")
                && !ownerTraceId.matches("0{32}") ? ownerTraceId.toLowerCase(Locale.ROOT) : null;
        Section<TraceSpans> spans;
        if (traceId == null) {
            spans = Section.pending("A valid trace identifier has not been recorded for this application yet.");
        } else if (client == null || apiKey.isBlank()) {
            spans = new Section<>("UNAVAILABLE", null, "TELEMETRY_NOT_CONFIGURED",
                    "Span data access is not configured for this environment.");
        } else {
            spans = read(applicationId, workflowId, traceId);
        }
        return Section.available(new Trace(applicationId, workflowId, traceId, publicUrl, spans));
    }

    private Section<TraceSpans> read(String applicationId, String workflowId, String traceId) {
        try {
            // SigNoz v0.134.0: POST is a read-only waterfall query, not an ingestion endpoint.
            return client.post().uri("/api/v4/traces/{id}/waterfall", traceId)
                    .header("SigNoz-Api-Key", apiKey).contentType(MediaType.APPLICATION_JSON)
                    .accept(MediaType.APPLICATION_JSON).body(Map.of("uncollapsedSpans", List.of()))
                    .exchange((request, response) -> {
                        int status = response.getStatusCode().value();
                        if (status == 401 || status == 403) {
                            return new Section<>("UNAVAILABLE", null, "TELEMETRY_ACCESS_DENIED",
                                    "Span data access is not authorized for this environment.");
                        }
                        MediaType type = response.getHeaders().getContentType();
                        if ((status != 200 && status != 404) || type == null || !MediaType.APPLICATION_JSON.isCompatibleWith(type))
                            return Section.error();
                        byte[] bytes = response.getBody().readNBytes(MAX_BYTES + 1);
                        if (bytes.length > MAX_BYTES) return Section.error();
                        JsonNode body = json.readTree(bytes);
                        if (status == 404) {
                            // Match only SigNoz's fixed trace-not-found diagnostic. Never reflect error text.
                            if ("error".equals(body.path("status").asText())
                                    && "trace not found".equals(body.path("error").path("message").asText()))
                                return Section.available(new TraceSpans(List.of(), false, 0L, false));
                            return new Section<>("UNAVAILABLE", null, "TELEMETRY_API_UNAVAILABLE",
                                    "The configured telemetry API could not locate span data.");
                        }
                        return Section.available(project(body, applicationId, workflowId, traceId));
                    });
        } catch (RuntimeException error) {
            // No upstream bodies, exception messages, prompts, attributes or credentials are logged.
            return Section.error();
        }
    }

    private TraceSpans project(JsonNode response, String applicationId, String workflowId, String traceId) {
        require("success".equals(response.path("status").asText()) && response.path("data").isObject());
        JsonNode data = response.path("data");
        JsonNode spans = data.path("spans");
        require(spans.isNull() || spans.isArray());
        require(spans.size() <= 10000);
        var items = new ArrayList<TraceSpan>();
        var ids = new HashSet<String>();
        for (JsonNode span : spans) {
            require(traceId.equalsIgnoreCase(span.path("trace_id").asText()));
            // SigNoz inserts placeholders for absent parents. They are not recorded spans.
            if ("Missing Span".equals(span.path("name").asText())) continue;
            JsonNode source = span.path("attributes");
            require(!source.has("application.id") || applicationId.equals(source.path("application.id").asText()));
            require(!source.has("workflow.id") || (workflowId != null && workflowId.equals(source.path("workflow.id").asText())));
            String id = span.path("span_id").asText();
            require(id.matches("[0-9a-fA-F]{16}") && !id.matches("0{16}"));
            id = id.toLowerCase(Locale.ROOT);
            require(ids.add(id));
            String parent = span.path("parent_span_id").asText("");
            require(parent.isEmpty() || parent.matches("[0-9a-fA-F]{16}"));
            parent = parent.isEmpty() || parent.matches("0{16}") ? null : parent.toLowerCase(Locale.ROOT);
            require(!id.equals(parent));
            require(span.path("time_unix").isIntegralNumber() && span.path("time_unix").canConvertToLong()
                    && span.path("duration_nano").isIntegralNumber() && span.path("duration_nano").canConvertToLong());
            long started = span.path("time_unix").asLong();
            long nanos = span.path("duration_nano").asLong();
            require(started > 0 && started <= Instant.now().plusSeconds(300).toEpochMilli() && nanos >= 0);
            String service = span.path("resource").path("service.name").asText();
            service = SERVICES.contains(service) ? service : "Other instrumented service";
            Map<String, String> attributes = attributes(span, applicationId, workflowId);
            String method = attributes.get("http.request.method");
            String db = attributes.get("db.operation");
            String ai = attributes.get("gen_ai.operation.name");
            String name = method != null ? method + " request" : db != null ? "Database " + db
                    : ai != null ? "AI " + ai : "Instrumented operation";
            String rawStatus = span.path("status_code_string").asText().toUpperCase(Locale.ROOT);
            String status = span.path("has_error").asBoolean(false) || span.path("status_code").asInt(0) == 2
                    || Set.of("ERROR", "STATUS_CODE_ERROR").contains(rawStatus) ? "ERROR"
                    : span.path("status_code").asInt(0) == 1 || Set.of("OK", "STATUS_CODE_OK").contains(rawStatus) ? "OK" : "UNSET";
            items.add(new TraceSpan(id, parent, service, name, Instant.ofEpochMilli(started),
                    BigDecimal.valueOf(nanos, 6), status, attributes));
        }
        items.sort(Comparator.comparing(TraceSpan::startedAt).thenComparing(TraceSpan::spanId));
        require(!data.path("totalSpansCount").isIntegralNumber() || data.path("totalSpansCount").canConvertToLong());
        Long total = data.path("totalSpansCount").isIntegralNumber() ? data.path("totalSpansCount").asLong() : null;
        require(total == null || (total >= 0 && total <= 9007199254740991L));
        boolean truncated = items.size() > 100 || data.path("hasMore").asBoolean(false)
                || (total != null && total > items.size());
        return new TraceSpans(items.stream().limit(100).toList(), truncated, total,
                data.path("hasMissingSpans").asBoolean(false));
    }

    private static Map<String, String> attributes(JsonNode span, String applicationId, String workflowId) {
        JsonNode source = span.path("attributes");
        var result = new LinkedHashMap<String, String>();
        String method = span.path("http_method").asText(source.path("http.request.method").asText(
                source.path("http.method").asText()));
        if (METHODS.contains(method)) result.put("http.request.method", method);
        String code = span.path("response_status_code").asText(source.path("http.response.status_code")
                .asText(source.path("http.status_code").asText()));
        if (code.matches("[1-5][0-9]{2}")) result.put("http.response.status_code", code);
        String db = span.path("db_operation").asText(source.path("db.operation").asText());
        if (DB_OPERATIONS.contains(db)) result.put("db.operation", db);
        String system = source.path("db.system").asText();
        if (Set.of("oracle", "postgresql", "mysql", "mariadb", "sqlite", "redis", "clickhouse").contains(system))
            result.put("db.system", system);
        String ai = source.path("gen_ai.operation.name").asText();
        if (Set.of("chat", "embeddings", "embedding", "text_completion").contains(ai))
            result.put("gen_ai.operation.name", ai);
        String provider = source.path("gen_ai.system").asText();
        if (Set.of("oci-genai", "oracle", "openai", "cohere").contains(provider)) result.put("gen_ai.system", provider);
        if (applicationId.equals(source.path("application.id").asText())) result.put("application.id", applicationId);
        if (workflowId != null && workflowId.equals(source.path("workflow.id").asText())) result.put("workflow.id", workflowId);
        return Map.copyOf(result);
    }

    private static String endpoint(String value) {
        if (value.isBlank()) return null;
        URI uri;
        try { uri = URI.create(value); } catch (IllegalArgumentException error) {
            throw new IllegalArgumentException("Invalid SigNoz endpoint configuration");
        }
        if (!Set.of("http", "https").contains(uri.getScheme()) || uri.getHost() == null
                || uri.getUserInfo() != null || uri.getQuery() != null || uri.getFragment() != null
                || !uri.getRawPath().matches("(?:/[A-Za-z0-9_-]+)*/?"))
            throw new IllegalArgumentException("Invalid SigNoz endpoint configuration");
        return value.replaceAll("/+$", "");
    }

    private static void require(boolean valid) {
        if (!valid) throw new IllegalArgumentException("Invalid telemetry projection");
    }
}
