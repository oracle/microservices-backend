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
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(
        classes = CloudBankSecurityAutoConfigurationTest.TestApplication.class,
        properties = {
            "eureka.client.enabled=false",
            "management.endpoints.web.exposure.include=health,info,env",
            "spring.cloud.config.import-check.enabled=false",
            "spring.cloud.discovery.enabled=false",
            "spring.security.oauth2.resourceserver.jwt.jwk-set-uri=http://example.invalid/oauth2/jwks"
        })
@AutoConfigureMockMvc
class CloudBankSecurityAutoConfigurationTest {

    @MockitoBean
    private JwtDecoder jwtDecoder;

    @Autowired
    private MockMvc mockMvc;

    @Test
    void readEndpointRequiresReadScope() throws Exception {
        mockMvc.perform(get("/api/v1/creditscore"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/api/v1/creditscore")
                .with(jwt().authorities(() -> "SCOPE_cloudbank.read")))
                .andExpect(status().isOk());
    }

    @Test
    void accountLookupAllowsInternalServiceScope() throws Exception {
        mockMvc.perform(get("/api/v1/account/27")
                .with(jwt().authorities(() -> "SCOPE_cloudbank.transfer")))
                .andExpect(status().isForbidden());

        mockMvc.perform(get("/api/v1/account/27")
                .with(jwt().authorities(() -> "SCOPE_cloudbank.internal")))
                .andExpect(status().isOk());
    }

    @Test
    void transferEndpointRequiresTransferScope() throws Exception {
        mockMvc.perform(post("/transfer")
                .contentType(MediaType.TEXT_PLAIN)
                .with(jwt().authorities(() -> "SCOPE_cloudbank.read")))
                .andExpect(status().isForbidden());

        mockMvc.perform(post("/transfer")
                .contentType(MediaType.TEXT_PLAIN)
                .with(jwt().authorities(() -> "SCOPE_cloudbank.transfer")))
                .andExpect(status().isOk());
    }

    @Test
    void internalEndpointRequiresInternalScopeByDefault() throws Exception {
        mockMvc.perform(post("/deposit")
                .contentType(MediaType.TEXT_PLAIN))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(post("/deposit")
                .contentType(MediaType.TEXT_PLAIN)
                .with(jwt().authorities(() -> "SCOPE_cloudbank.internal")))
                .andExpect(status().isOk());
    }

    @Test
    void onlyHealthAndInfoActuatorEndpointsArePublic() throws Exception {
        mockMvc.perform(get("/actuator/health"))
                .andExpect(status().isOk());

        mockMvc.perform(get("/actuator/env"))
                .andExpect(status().isUnauthorized());
    }

    @SpringBootApplication
    @Import({CloudBankSecurityAutoConfiguration.class, TestController.class})
    static class TestApplication {
    }

    @RestController
    static class TestController {
        @GetMapping("/api/v1/creditscore")
        String read() {
            return "ok";
        }

        @GetMapping("/api/v1/account/27")
        String accountLookup() {
            return "ok";
        }

        @PostMapping("/transfer")
        String transfer() {
            return "ok";
        }

        @PostMapping("/deposit")
        String deposit() {
            return "ok";
        }

        @PostMapping("/chat")
        String chat() {
            return "ok";
        }
    }
}
