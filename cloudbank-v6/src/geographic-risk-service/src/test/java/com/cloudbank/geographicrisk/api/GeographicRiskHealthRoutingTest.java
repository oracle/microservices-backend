// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.api;

import io.helidon.config.Config;
import io.helidon.jersey.webserver.JaxRsService;
import io.helidon.webserver.WebServer;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import org.glassfish.jersey.server.ResourceConfig;
import org.junit.jupiter.api.Test;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

import static org.assertj.core.api.Assertions.assertThat;

class GeographicRiskHealthRoutingTest {
    @Test
    void applicationErrorMapperAllowsHealthRequestsToReachHelidonRoutes() throws Exception {
        ResourceConfig resources = new ResourceConfig()
                .register(new FailureResource())
                .register(GeographicRiskExceptionMapper.class);
        WebServer server = WebServer.builder().host("127.0.0.1").port(0)
                .routing(routing -> routing
                        .register(JaxRsService.create(Config.empty(), resources))
                        .get("/health/live", (request, response) -> response.send("UP"))
                        .get("/health/ready", (request, response) -> response.send("UP")))
                .build().start();
        try (HttpClient client = HttpClient.newHttpClient()) {
            for (String path : new String[]{"/health/live", "/health/ready"}) {
                var response = get(client, server, path);
                assertThat(response.statusCode()).isEqualTo(200);
                assertThat(response.body()).isEqualTo("UP");
            }
            var failure = get(client, server, "/internal/synthetic-failure");
            assertThat(failure.statusCode()).isEqualTo(500);
            assertThat(failure.body()).contains("EVALUATION_FAILED").doesNotContain("private detail");
        } finally {
            server.stop();
        }
    }

    private static HttpResponse<String> get(HttpClient client, WebServer server, String path) throws Exception {
        return client.send(HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + server.port() + path))
                .GET().build(), HttpResponse.BodyHandlers.ofString());
    }

    @Path("/internal/synthetic-failure")
    public static class FailureResource {
        @GET
        public String fail() {
            throw new GeographicRiskApiException(new IllegalStateException("private detail"));
        }
    }
}
