// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.

package com.cloudbank.workflowtokenrefresh.microtx;

import com.cloudbank.workflowtokenrefresh.config.TokenRefreshWorkerProperties;
import com.cloudbank.workflowtokenrefresh.oauth.FreshTokenProvider;
import com.cloudbank.workflowtokenrefresh.oauth.FreshTokenProvider.AccessToken;
import java.util.Map;
import java.util.Optional;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClient;
import tools.jackson.databind.JsonNode;

@Component
public class RestMicroTxTaskClient implements MicroTxTaskClient {
    private final RestClient restClient;
    private final FreshTokenProvider tokenProvider;
    private final String taskType;
    private final String workerId;

    public RestMicroTxTaskClient(RestClient.Builder builder, TokenRefreshWorkerProperties properties,
            @Qualifier("microTxTokenProvider") FreshTokenProvider tokenProvider) {
        this.restClient = builder.baseUrl(normalizeApiBase(properties.microtx().baseUrl())).build();
        this.tokenProvider = tokenProvider;
        this.taskType = properties.taskType();
        this.workerId = properties.workerId();
    }

    @Override
    public Optional<PolledTask> poll() {
        JsonNode response = withTokenRetry(token -> restClient.get()
                .uri(uri -> uri.path("/tasks/poll/{taskType}").queryParam("workerid", workerId).build(taskType))
                .header("Authorization", "Bearer " + token.value())
                .retrieve()
                .body(JsonNode.class));
        if (response == null) {
            return Optional.empty();
        }
        String taskId = response.path("taskId").asText(null);
        String workflowInstanceId = response.path("workflowInstanceId").asText(null);
        if (!StringUtils.hasText(taskId) || !StringUtils.hasText(workflowInstanceId)) {
            return Optional.empty();
        }
        return Optional.of(new PolledTask(taskId, workflowInstanceId));
    }

    @Override
    public void complete(PolledTask task, AccessToken refreshedToken) {
        Map<String, Object> result = Map.of(
                "workflowInstanceId", task.workflowInstanceId(),
                "taskId", task.taskId(),
                "workerId", workerId,
                "status", "COMPLETED",
                "outputData", Map.of(
                        "workflowTaskAuthorization", "Bearer " + refreshedToken.value(),
                        "expiresAtEpochSecond", refreshedToken.expiresAt().getEpochSecond()));
        update(result);
    }

    @Override
    public void fail(PolledTask task, String reason) {
        Map<String, Object> result = Map.of(
                "workflowInstanceId", task.workflowInstanceId(),
                "taskId", task.taskId(),
                "workerId", workerId,
                "status", "FAILED",
                "reasonForIncompletion", reason,
                "outputData", Map.of("errorCode", "WORKFLOW_TASK_TOKEN_REFRESH_FAILED"));
        update(result);
    }

    private void update(Map<String, Object> result) {
        withTokenRetry(token -> {
            restClient.post().uri("/tasks")
                    .header("Authorization", "Bearer " + token.value())
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(result)
                    .retrieve()
                    .toBodilessEntity();
            return null;
        });
    }

    private <T> T withTokenRetry(AuthenticatedCall<T> call) {
        try {
            return call.execute(tokenProvider.accessToken());
        } catch (HttpClientErrorException.Unauthorized exception) {
            tokenProvider.invalidate();
            return call.execute(tokenProvider.accessToken());
        }
    }

    private static String normalizeApiBase(String value) {
        String base = value == null ? "" : value.replaceAll("/+$", "");
        return base.endsWith("/api") ? base : base + "/api";
    }

    @FunctionalInterface
    private interface AuthenticatedCall<T> {
        T execute(AccessToken token);
    }
}
