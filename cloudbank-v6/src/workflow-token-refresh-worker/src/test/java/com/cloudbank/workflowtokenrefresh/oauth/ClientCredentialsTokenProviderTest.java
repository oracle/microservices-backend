// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.

package com.cloudbank.workflowtokenrefresh.oauth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

class ClientCredentialsTokenProviderTest {

    @Test
    void obtainsAndCachesAClientCredentialsTokenWithoutExposingTheSecretInOutput() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo("http://azn-server:8080/oauth2/token"))
                .andExpect(header("Authorization", "Basic d29ya2VyOnNlY3JldA=="))
                .andRespond(withSuccess("""
                        {"access_token":"fresh-token","token_type":"Bearer","expires_in":300}
                        """, MediaType.APPLICATION_JSON));
        var provider = new ClientCredentialsTokenProvider(builder.build(),
                Clock.fixed(Instant.parse("2026-08-24T10:00:00Z"), ZoneOffset.UTC),
                "http://azn-server:8080/oauth2/token", "worker", "secret", "cloudbank.internal");

        var first = provider.accessToken();
        var cached = provider.accessToken();

        assertThat(first.value()).isEqualTo("fresh-token");
        assertThat(first.expiresAt()).isEqualTo(Instant.parse("2026-08-24T10:05:00Z"));
        assertThat(cached).isSameAs(first);
        server.verify();
    }
}
