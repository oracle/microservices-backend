// Copyright (c) 2026, Oracle and/or its affiliates.

package com.example.common.security;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RestController;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(
        classes = CloudBankInternalSecurityAutoConfigurationTest.TestApplication.class,
        properties = {
            "cloudbank.security.require-internal-token=true",
            "eureka.client.enabled=false",
            "spring.cloud.config.import-check.enabled=false",
            "spring.cloud.discovery.enabled=false",
            "spring.security.oauth2.resourceserver.jwt.jwk-set-uri=http://example.invalid/oauth2/jwks"
        })
@AutoConfigureMockMvc
class CloudBankInternalSecurityAutoConfigurationTest {

    @MockitoBean
    private JwtDecoder jwtDecoder;

    @Autowired
    private MockMvc mockMvc;

    @Test
    void serviceToServiceEndpointRequiresInternalScope() throws Exception {
        mockMvc.perform(post("/api/v1/account/journal")
                .contentType(MediaType.APPLICATION_JSON))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(post("/api/v1/account/journal")
                .contentType(MediaType.APPLICATION_JSON)
                .with(jwt().authorities(() -> "SCOPE_cloudbank.internal")))
                .andExpect(status().isOk());
    }

    @Test
    void microtxCallbackSubpathsRemainCompatible() throws Exception {
        mockMvc.perform(put("/deposit/complete")
                .contentType(MediaType.TEXT_PLAIN))
                .andExpect(status().isOk());
    }

    @SpringBootApplication
    @Import({CloudBankSecurityAutoConfiguration.class, TestController.class})
    static class TestApplication {
    }

    @RestController
    static class TestController {

        @PostMapping("/api/v1/account/journal")
        String journal() {
            return "ok";
        }

        @PutMapping("/deposit/complete")
        String complete() {
            return "ok";
        }
    }
}
