// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.workflow;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.Objects;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;

@Component
@ConditionalOnProperty(prefix = "cloudbank.workflow", name = "mode", havingValue = "microtx")
public class MicroTxWorkflowStarter implements WorkflowStarter {

    private final RestClient restClient;
    private final RestClient tokenClient;
    private final ObjectMapper objectMapper;
    private final OAuthClient workflowClient;
    private final OAuthClient taskClient;

    @Autowired
    public MicroTxWorkflowStarter(RestClient.Builder builder, ObjectMapper objectMapper,
            @Value("${cloudbank.workflow.base-url}") String baseUrl,
            @Value("${cloudbank.workflow.token-uri}") String tokenUri,
            @Value("${cloudbank.workflow.client-id}") String clientId,
            @Value("${cloudbank.workflow.client-secret}") String clientSecret,
            @Value("${cloudbank.workflow.scope}") String scope,
            @Value("${cloudbank.workflow.task-token-uri}") String taskTokenUri,
            @Value("${cloudbank.workflow.task-client-id}") String taskClientId,
            @Value("${cloudbank.workflow.task-client-secret}") String taskClientSecret,
            @Value("${cloudbank.workflow.task-scope}") String taskScope) {
        this(workflowRestClient(builder, baseUrl), RestClient.create(), objectMapper,
                new OAuthClient(tokenUri, clientId, clientSecret, scope),
                new OAuthClient(taskTokenUri, taskClientId, taskClientSecret, taskScope));
    }

    MicroTxWorkflowStarter(RestClient restClient, RestClient tokenClient, ObjectMapper objectMapper,
            OAuthClient workflowClient, OAuthClient taskClient) {
        validateOAuthClient(workflowClient, "MicroTx Workflow API");
        validateOAuthClient(taskClient, "workflow task");
        this.restClient = Objects.requireNonNull(restClient, "restClient");
        this.tokenClient = Objects.requireNonNull(tokenClient, "tokenClient");
        this.objectMapper = Objects.requireNonNull(objectMapper, "objectMapper");
        this.workflowClient = workflowClient;
        this.taskClient = taskClient;
    }

    @Override
    public WorkflowExecution start(StartWorkflowCommand command) {
        String workflowToken = accessToken(workflowClient, "MICROTX_TOKEN_FAILURE");
        String taskToken = accessToken(taskClient, "WORKFLOW_TASK_TOKEN_FAILURE");
        String payload = workflowPayload(command.payload(), taskToken);
        try {
            return submit(command, payload, workflowToken);
        } catch (RestClientResponseException exception) {
            if (exception.getStatusCode().value() == 404) {
                warmWorkflowDefinition(command, workflowToken);
                try {
                    return submit(command, payload, workflowToken);
                } catch (RestClientResponseException retryException) {
                    throw workflowHttpException(retryException);
                }
            }
            throw workflowHttpException(exception);
        }
    }

    private WorkflowExecution submit(StartWorkflowCommand command, String payload, String workflowToken) {
        RestClient.RequestBodySpec request = restClient.post().uri(uriBuilder -> uriBuilder.path("/api/workflow/{name}")
                .queryParam("version", command.workflowVersion()).queryParam("correlationId", command.applicationId())
                .queryParam("idempotencyKey", command.idempotencyKey()).build(command.workflowName()))
                .contentType(MediaType.APPLICATION_JSON)
                .header("traceparent", "00-" + command.traceId() + "-0000000000000001-01");
        request = request.header("Authorization", "Bearer " + workflowToken);
        String response = request.body(payload).retrieve().body(String.class);
        return workflowExecution(response);
    }

    private void warmWorkflowDefinition(StartWorkflowCommand command, String workflowToken) {
        try {
            restClient.get().uri(uriBuilder -> uriBuilder.path("/api/metadata/workflow/{name}")
                    .queryParam("version", command.workflowVersion()).build(command.workflowName()))
                    .header("Authorization", "Bearer " + workflowToken).retrieve().toBodilessEntity();
        } catch (RestClientException ignored) {
            // Preserve the original start semantics; the bounded outbox retry remains the fallback.
        }
    }

    private static WorkflowStartException workflowHttpException(RestClientResponseException exception) {
        int status = exception.getStatusCode().value();
        boolean retryable = status == 404 || status == 429 || status >= 500;
        return new WorkflowStartException("MICROTX_HTTP_" + status, retryable, exception);
    }

    private static RestClient workflowRestClient(RestClient.Builder builder, String baseUrl) {
        if (!StringUtils.hasText(baseUrl)) {
            throw new IllegalStateException("MicroTx mode requires base URL");
        }
        return builder.baseUrl(baseUrl).build();
    }

    private WorkflowExecution workflowExecution(String response) {
        if (!StringUtils.hasText(response)) {
            throw new WorkflowStartException("MICROTX_EMPTY_RESPONSE", true);
        }
        String responseBody = response.trim();
        String workflowId = responseBody;
        String status = "STARTED";
        try {
            JsonNode json = objectMapper.readTree(responseBody);
            if (json.isTextual()) {
                workflowId = json.asText();
            } else if (json.isObject()) {
                workflowId = json.path("workflowId").asText(json.path("workflow_id").asText());
                status = json.path("status").asText(status);
            }
        } catch (JsonProcessingException exception) {
            workflowId = responseBody;
        }
        if (!StringUtils.hasText(workflowId)) {
            throw new WorkflowStartException("MICROTX_INVALID_RESPONSE", false);
        }
        return new WorkflowExecution(workflowId, status);
    }

    private String accessToken(OAuthClient client, String failureCode) {
        String basic = Base64.getEncoder()
                .encodeToString((client.clientId() + ":" + client.clientSecret()).getBytes(StandardCharsets.UTF_8));
        try {
            String response = tokenClient.post().uri(client.tokenUri())
                    .contentType(MediaType.APPLICATION_FORM_URLENCODED).header("Authorization", "Basic " + basic)
                    .body("grant_type=client_credentials&scope=" + client.scope()).retrieve().body(String.class);
            String token = StringUtils.hasText(response) ? objectMapper.readTree(response).path("access_token").asText()
                    : null;
            if (!StringUtils.hasText(token)) {
                throw new WorkflowStartException(failureCode, true);
            }
            return token;
        } catch (JsonProcessingException | RestClientException exception) {
            throw new WorkflowStartException(failureCode, true);
        }
    }

    private String workflowPayload(String payload, String token) {
        ObjectNode input = validatedPayload(payload);
        input.put("workflowTaskAuthorization", "Bearer " + token);
        try {
            return objectMapper.writeValueAsString(input);
        } catch (JsonProcessingException exception) {
            throw new WorkflowStartException("WORKFLOW_PAYLOAD_INVALID", false);
        }
    }

    private ObjectNode validatedPayload(String payload) {
        if (!StringUtils.hasText(payload)) {
            throw new WorkflowStartException("WORKFLOW_PAYLOAD_INVALID", false);
        }
        try {
            JsonNode input = objectMapper.readTree(payload);
            if (!input.isObject()) {
                throw new WorkflowStartException("WORKFLOW_PAYLOAD_INVALID", false);
            }
            return (ObjectNode) input;
        } catch (JsonProcessingException exception) {
            throw new WorkflowStartException("WORKFLOW_PAYLOAD_INVALID", false);
        }
    }

    private static void validateOAuthClient(OAuthClient client, String purpose) {
        Objects.requireNonNull(client, "client");
        boolean complete = StringUtils.hasText(client.tokenUri()) && StringUtils.hasText(client.clientId())
                && StringUtils.hasText(client.clientSecret()) && StringUtils.hasText(client.scope());
        if (!complete) {
            throw new IllegalStateException(
                    "MicroTx mode requires token URI, client ID, client secret, and scope for " + purpose);
        }
    }

    record OAuthClient(String tokenUri, String clientId, String clientSecret, String scope) {
    }

    public static class WorkflowStartException extends RuntimeException {
        private final String code;
        private final boolean retryable;

        WorkflowStartException(String code, boolean retryable) {
            super(code);
            this.code = code;
            this.retryable = retryable;
        }

        WorkflowStartException(String code, boolean retryable, Throwable cause) {
            super(code, cause);
            this.code = code;
            this.retryable = retryable;
        }

        public String code() {
            return code;
        }

        public boolean retryable() {
            return retryable;
        }
    }
}
