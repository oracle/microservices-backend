// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.

package com.cloudbank.workflowtokenrefresh.worker;

import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.cloudbank.workflowtokenrefresh.config.TokenRefreshWorkerProperties;
import com.cloudbank.workflowtokenrefresh.microtx.MicroTxTaskClient;
import com.cloudbank.workflowtokenrefresh.microtx.MicroTxTaskClient.PolledTask;
import com.cloudbank.workflowtokenrefresh.oauth.FreshTokenProvider;
import com.cloudbank.workflowtokenrefresh.oauth.FreshTokenProvider.AccessToken;
import java.time.Instant;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

class TokenRefreshTaskWorkerTest {

    @Test
    void refreshesTheTokenAndCompletesThePolledTask() {
        MicroTxTaskClient microTx = Mockito.mock(MicroTxTaskClient.class);
        FreshTokenProvider tokens = Mockito.mock(FreshTokenProvider.class);
        PolledTask task = new PolledTask("task-1", "workflow-1");
        AccessToken token = new AccessToken("fresh-token", Instant.parse("2026-08-24T10:05:00Z"));
        when(microTx.poll()).thenReturn(Optional.of(task));
        when(tokens.accessToken()).thenReturn(token);

        new TokenRefreshTaskWorker(properties("microtx"), microTx, tokens).pollOnce();

        verify(tokens).invalidate();
        verify(microTx).complete(task, token);
        verify(microTx, never()).fail(Mockito.any(), Mockito.anyString());
    }

    @Test
    void remainsIdleOutsideMicroTxMode() {
        MicroTxTaskClient microTx = Mockito.mock(MicroTxTaskClient.class);
        FreshTokenProvider tokens = Mockito.mock(FreshTokenProvider.class);

        new TokenRefreshTaskWorker(properties("fake"), microTx, tokens).pollOnce();

        verify(microTx, never()).poll();
        verify(tokens, never()).accessToken();
    }

    @Test
    void reportsASafeRetryableFailureWhenTokenAcquisitionFails() {
        MicroTxTaskClient microTx = Mockito.mock(MicroTxTaskClient.class);
        FreshTokenProvider tokens = Mockito.mock(FreshTokenProvider.class);
        PolledTask task = new PolledTask("task-1", "workflow-1");
        when(microTx.poll()).thenReturn(Optional.of(task));
        when(tokens.accessToken()).thenThrow(new IllegalStateException("sensitive remote response"));

        new TokenRefreshTaskWorker(properties("microtx"), microTx, tokens).pollOnce();

        verify(microTx).fail(task, "Fresh workflow task authorization could not be obtained");
        verify(microTx, never()).complete(Mockito.any(), Mockito.any());
    }

    private static TokenRefreshWorkerProperties properties(String mode) {
        var microTx = new TokenRefreshWorkerProperties.MicroTx("http://microtx/workflow-server",
                "http://azn/oauth2/token", "microtx-worker", "microtx-secret", "microtx.workflow");
        var task = new TokenRefreshWorkerProperties.OAuthClient("http://azn/oauth2/token",
                "cloudbank-service-client", "cloudbank-secret", "cloudbank.internal");
        return new TokenRefreshWorkerProperties(mode, "refresh_workflow_authorization", "worker-1", 1000,
                microTx, task);
    }
}
