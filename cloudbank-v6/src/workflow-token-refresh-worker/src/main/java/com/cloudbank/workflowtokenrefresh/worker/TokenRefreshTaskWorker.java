// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.

package com.cloudbank.workflowtokenrefresh.worker;

import com.cloudbank.workflowtokenrefresh.config.TokenRefreshWorkerProperties;
import com.cloudbank.workflowtokenrefresh.microtx.MicroTxTaskClient;
import com.cloudbank.workflowtokenrefresh.oauth.FreshTokenProvider;
import java.util.concurrent.atomic.AtomicBoolean;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class TokenRefreshTaskWorker {
    private static final Logger LOGGER = LoggerFactory.getLogger(TokenRefreshTaskWorker.class);
    private static final String SAFE_FAILURE_REASON = "Fresh workflow task authorization could not be obtained";

    private final TokenRefreshWorkerProperties properties;
    private final MicroTxTaskClient microTx;
    private final FreshTokenProvider workflowTaskTokenProvider;
    private final AtomicBoolean connectivityWarningLogged = new AtomicBoolean();

    public TokenRefreshTaskWorker(TokenRefreshWorkerProperties properties, MicroTxTaskClient microTx,
            @Qualifier("workflowTaskTokenProvider") FreshTokenProvider workflowTaskTokenProvider) {
        this.properties = properties;
        this.microTx = microTx;
        this.workflowTaskTokenProvider = workflowTaskTokenProvider;
    }

    @Scheduled(fixedDelayString = "${cloudbank.token-refresh-worker.poll-delay-ms:1000}")
    public void pollOnce() {
        if (!properties.enabled()) {
            return;
        }
        try {
            microTx.poll().ifPresent(this::refresh);
            connectivityWarningLogged.set(false);
        } catch (RuntimeException exception) {
            if (connectivityWarningLogged.compareAndSet(false, true)) {
                LOGGER.warn("MicroTx token-refresh worker polling is unavailable ({})",
                        exception.getClass().getSimpleName());
            }
        }
    }

    private void refresh(MicroTxTaskClient.PolledTask task) {
        FreshTokenProvider.AccessToken refreshedToken;
        try {
            workflowTaskTokenProvider.invalidate();
            refreshedToken = workflowTaskTokenProvider.accessToken();
        } catch (RuntimeException exception) {
            LOGGER.warn("Workflow task authorization refresh failed for task {} ({})", task.taskId(),
                    exception.getClass().getSimpleName());
            microTx.fail(task, SAFE_FAILURE_REASON);
            return;
        }
        microTx.complete(task, refreshedToken);
    }
}
