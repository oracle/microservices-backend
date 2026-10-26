// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.

package com.cloudbank.workflowtokenrefresh.config;

import com.cloudbank.workflowtokenrefresh.oauth.ClientCredentialsTokenProvider;
import com.cloudbank.workflowtokenrefresh.oauth.FreshTokenProvider;
import java.time.Clock;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.util.StringUtils;
import org.springframework.web.client.RestClient;

@Configuration
public class WorkerConfiguration {

    @Bean
    @ConditionalOnMissingBean(RestClient.Builder.class)
    RestClient.Builder restClientBuilder() {
        return RestClient.builder();
    }

    @Bean
    Clock clock() {
        return Clock.systemUTC();
    }

    @Bean("microTxTokenProvider")
    FreshTokenProvider microTxTokenProvider(RestClient.Builder builder, Clock clock,
            TokenRefreshWorkerProperties properties) {
        var client = properties.microtx();
        return new ClientCredentialsTokenProvider(builder.build(), clock, client.tokenUri(), client.clientId(),
                client.clientSecret(), client.scope());
    }

    @Bean("workflowTaskTokenProvider")
    FreshTokenProvider workflowTaskTokenProvider(RestClient.Builder builder, Clock clock,
            TokenRefreshWorkerProperties properties) {
        var client = properties.taskToken();
        return new ClientCredentialsTokenProvider(builder.build(), clock, client.tokenUri(), client.clientId(),
                client.clientSecret(), client.scope());
    }

    @Bean
    WorkerConfigurationValidator workerConfigurationValidator(TokenRefreshWorkerProperties properties,
            @Qualifier("microTxTokenProvider") FreshTokenProvider ignoredMicroTxProvider,
            @Qualifier("workflowTaskTokenProvider") FreshTokenProvider ignoredTaskProvider) {
        return new WorkerConfigurationValidator(properties);
    }

    static final class WorkerConfigurationValidator {
        WorkerConfigurationValidator(TokenRefreshWorkerProperties properties) {
            if (!properties.enabled()) {
                return;
            }
            require("WORKFLOW_TOKEN_REFRESH_TASK_TYPE", properties.taskType());
            require("WORKFLOW_TOKEN_REFRESH_WORKER_ID", properties.workerId());
            require("MICROTX_WORKFLOW_URL", properties.microtx().baseUrl());
            require("WORKFLOW_TOKEN_REFRESH_MICROTX_TOKEN_URI", properties.microtx().tokenUri());
            require("WORKFLOW_TOKEN_REFRESH_MICROTX_CLIENT_ID", properties.microtx().clientId());
            require("WORKFLOW_TOKEN_REFRESH_MICROTX_CLIENT_SECRET", properties.microtx().clientSecret());
            require("WORKFLOW_TOKEN_REFRESH_MICROTX_SCOPE", properties.microtx().scope());
            require("WORKFLOW_TOKEN_REFRESH_TASK_TOKEN_URI", properties.taskToken().tokenUri());
            require("WORKFLOW_TOKEN_REFRESH_TASK_CLIENT_ID", properties.taskToken().clientId());
            require("WORKFLOW_TOKEN_REFRESH_TASK_CLIENT_SECRET", properties.taskToken().clientSecret());
            require("WORKFLOW_TOKEN_REFRESH_TASK_SCOPE", properties.taskToken().scope());
        }

        private static void require(String name, String value) {
            if (!StringUtils.hasText(value)) {
                throw new IllegalStateException(name + " is required when WORKFLOW_MODE=microtx");
            }
        }
    }
}
