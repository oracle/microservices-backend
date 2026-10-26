// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.

package com.cloudbank.workflowtokenrefresh.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties("cloudbank.token-refresh-worker")
public record TokenRefreshWorkerProperties(
        String mode,
        String taskType,
        String workerId,
        long pollDelayMs,
        MicroTx microtx,
        OAuthClient taskToken) {

    public boolean enabled() {
        return "microtx".equalsIgnoreCase(mode);
    }

    public record MicroTx(String baseUrl, String tokenUri, String clientId, String clientSecret, String scope) {
    }

    public record OAuthClient(String tokenUri, String clientId, String clientSecret, String scope) {
    }
}
