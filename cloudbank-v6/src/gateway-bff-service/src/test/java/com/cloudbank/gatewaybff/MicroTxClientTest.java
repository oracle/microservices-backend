// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.gatewaybff;

import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.*;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

class MicroTxClientTest {
    @Test
    void usesServerSideClientCredentialsAndCompletesRejectedOutcomesAsCompletedTasks() throws Exception {
        var tokenCalls = new AtomicInteger();
        var tokenServer = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        tokenServer.createContext("/oauth2/token", exchange -> {
            tokenCalls.incrementAndGet();
            assertThat(exchange.getRequestHeaders().getFirst("Authorization")).startsWith("Basic ");
            assertThat(new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8))
                    .contains("grant_type=client_credentials", "scope=microtx.workflow");
            byte[] response = """
                    {"access_token":"synthetic-microtx-token","token_type":"Bearer","expires_in":300,"scope":"microtx.workflow"}
                    """.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Content-Type", "application/json");
            exchange.sendResponseHeaders(200, response.length);
            exchange.getResponseBody().write(response);
            exchange.close();
        });
        tokenServer.start();
        try {
            var builder = RestClient.builder();
            var upstream = MockRestServiceServer.bindTo(builder).build();
            var client = new MicroTxClient(builder, "http://microtx.example/workflow-server/api/",
                    "http://127.0.0.1:" + tokenServer.getAddress().getPort() + "/oauth2/token",
                    "synthetic-client", "synthetic-secret");
            upstream.expect(requestTo("http://microtx.example/workflow-server/api/notifications/human-tasks?start=0&size=100"))
                    .andExpect(header("Authorization", "Bearer synthetic-microtx-token"))
                    .andExpect(header("X-Correlation-ID", "safe-correlation"))
                    .andRespond(withSuccess("{\"totalHits\":0,\"results\":[]}", MediaType.APPLICATION_JSON));
            upstream.expect(requestTo("http://microtx.example/workflow-server/api/tasks/wf-one/human_task_manual_review/COMPLETED"))
                    .andExpect(method(HttpMethod.POST))
                    .andExpect(header("Authorization", "Bearer synthetic-microtx-token"))
                    .andExpect(header("Idempotency-Key", "resolution-one"))
                    .andExpect(content().json("""
                            {"decisionOutcome":"REJECTED","reviewerRole":"UNDERWRITER","reviewerPrincipalId":"signed-reviewer",
                             "reasonCode":"DOCUMENT_EXCEPTION_RESOLVED","policySection":"CBPL-150-S4"}
                            """))
                    .andRespond(withSuccess("task-one", MediaType.TEXT_PLAIN));
            assertThat(client.pending(0, 100, "safe-correlation").results()).isEmpty();
            client.complete("wf-one", new MicroTxClient.Completion("REJECTED", "UNDERWRITER", "signed-reviewer",
                    "DOCUMENT_EXCEPTION_RESOLVED", "CBPL-150-S4"), "resolution-one", "safe-correlation");
            assertThat(tokenCalls).hasValue(1);
            upstream.verify();
        } finally {
            tokenServer.stop(0);
        }
    }

    @Test
    void absentMicroTxConfigurationFailsClosedWithoutBreakingOtherBffFeatures() {
        var client = new MicroTxClient(RestClient.builder(), "", "", "microtx-workflow-client", "");
        assertThatThrownBy(() -> client.pending(0, 100, "safe-correlation"))
                .isInstanceOfSatisfying(ResponseStatusException.class,
                        error -> assertThat(error.getStatusCode().value()).isEqualTo(503));
    }
}
