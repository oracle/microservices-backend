// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.decision.api;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.cloudbank.decision.domain.DecisionModels.DecisionOutcome;
import com.cloudbank.decision.domain.DecisionModels.DecisionResult;
import com.cloudbank.decision.domain.DecisionModels.DecisionType;
import com.cloudbank.decision.security.InternalAuthorization;
import com.cloudbank.decision.security.SecurityConfig;
import com.cloudbank.decision.service.DecisionService;
import java.util.List;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockServletContext;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientService;
import org.springframework.security.oauth2.client.registration.ClientRegistrationRepository;
import org.springframework.test.context.support.TestPropertySourceUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.support.AnnotationConfigWebApplicationContext;
import org.springframework.web.servlet.config.annotation.EnableWebMvc;
import org.testng.annotations.AfterMethod;
import org.testng.annotations.BeforeMethod;
import org.testng.annotations.Test;

public class DecisionControllerSecurityTest {
    private AnnotationConfigWebApplicationContext context;
    private MockMvc mockMvc;
    private DecisionService service;

    @BeforeMethod
    public void setUp() {
        service = mock(DecisionService.class);
        context = new AnnotationConfigWebApplicationContext();
        context.setServletContext(new MockServletContext());
        TestPropertySourceUtils.addInlinedPropertiesToEnvironment(context,
                "spring.security.oauth2.resourceserver.jwt.jwk-set-uri=http://authorization.invalid/jwks",
                "spring.security.oauth2.resourceserver.jwt.issuer-uri=http://authorization.invalid");
        context.addBeanFactoryPostProcessor(beanFactory -> {
            beanFactory.registerSingleton("decisionService", service);
            beanFactory.registerSingleton("clientRegistrationRepository",
                    mock(ClientRegistrationRepository.class));
            beanFactory.registerSingleton("oauth2AuthorizedClientService",
                    mock(OAuth2AuthorizedClientService.class));
        });
        context.register(WebTestConfiguration.class);
        context.refresh();
        mockMvc = MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();
    }

    @AfterMethod
    public void tearDown() {
        context.close();
    }

    @Test
    public void internalEndpointsRejectAnonymousAndUserCallers() throws Exception {
        mockMvc.perform(get("/internal/api/v1/decisions/DEC-00000000000000000000000000000000"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/internal/api/v1/decisions/DEC-00000000000000000000000000000000")
                .with(token("cloudbank-service-client", "user", "SCOPE_cloudbank.internal")))
                .andExpect(status().isForbidden());
    }

    @Test
    public void eligibleServiceTokenCanRequestAnInitialDecision() throws Exception {
        when(service.decide(any(), eq("decision:initial:APP-ONE:WF-ONE"))).thenReturn(result());

        MvcResult response = mockMvc.perform(post("/internal/api/v1/decisions")
                .with(token("cloudbank-service-client", "service", "SCOPE_cloudbank.internal"))
                .header("Idempotency-Key", "decision:initial:APP-ONE:WF-ONE")
                .contentType(MediaType.APPLICATION_JSON).content("""
                        {
                          "applicationId":"APP-ONE",
                          "workflowId":"WF-ONE",
                          "taskReference":"deterministic_initial_decision",
                          "traceId":"0123456789abcdef0123456789abcdef",
                          "decisionType":"INITIAL",
                          "evidence":{
                            "documentReviewId":"DREV-0123456789abcdef0123456789abcdef",
                            "documentDisposition":"CLEAR",
                            "policySupportId":"AIPOL-ONE",
                            "policyEvidenceStatus":"GROUNDED",
                            "policyCitations":[],
                            "geographicRiskEvaluationId":"GEO-ONE",
                            "geographicRiskDisposition":"CLEAR"
                          }
                        }
                        """))
                .andExpect(status().isOk())
                .andReturn();

        assertThat(response.getResponse().getContentAsString())
                .contains("\"outcome\":\"APPROVED\"")
                .contains("\"decisionSource\":\"DETERMINISTIC_POLICY_RULES\"");
        verify(service).decide(any(), eq("decision:initial:APP-ONE:WF-ONE"));
    }

    @Test
    public void invalidManualResolutionReportsFieldNamesWithoutRejectedValues() throws Exception {
        MvcResult response = mockMvc.perform(post("/internal/api/v1/decisions")
                .with(token("cloudbank-service-client", "service", "SCOPE_cloudbank.internal"))
                .header("Idempotency-Key", "decision:manual-final:APP-ONE:WF-ONE")
                .contentType(MediaType.APPLICATION_JSON).content("""
                        {
                          "applicationId":"APP-ONE",
                          "workflowId":"WF-ONE",
                          "taskReference":"deterministic_manual_final_decision",
                          "traceId":"0123456789abcdef0123456789abcdef",
                          "decisionType":"MANUAL_FINAL",
                          "evidence":{
                            "documentReviewId":"DREV-0123456789abcdef0123456789abcdef",
                            "documentDisposition":"MANUAL_REVIEW",
                            "policySupportId":"AIPOL-ONE",
                            "policyEvidenceStatus":"GROUNDED",
                            "policyCitations":[],
                            "geographicRiskEvaluationId":"GEO-ONE",
                            "geographicRiskDisposition":"NOT_EVALUATED"
                          },
                          "manualReview":{
                            "outcome":null,
                            "reviewerRole":"",
                            "reviewerPrincipalId":"private-reviewer-value",
                            "reasonCode":"invalid reason",
                            "policySection":"invalid section"
                          }
                        }
                        """))
                .andExpect(status().isBadRequest())
                .andReturn();

        assertThat(response.getResponse().getContentAsString())
                .contains("\"field\":\"manualReview.outcome\"")
                .contains("\"field\":\"manualReview.reviewerRole\"")
                .contains("\"field\":\"manualReview.reasonCode\"")
                .contains("\"field\":\"manualReview.policySection\"")
                .doesNotContain("private-reviewer-value")
                .doesNotContain("invalid reason")
                .doesNotContain("invalid section");
    }

    private static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.JwtRequestPostProcessor token(
            String clientId, String tokenKind, String authority) {
        return jwt().jwt(value -> value.claim("client_id", clientId).claim("token_kind", tokenKind)
                .claim("scope", authority.substring("SCOPE_".length())))
                .authorities(new SimpleGrantedAuthority(authority));
    }

    private static DecisionResult result() {
        return new DecisionResult("DEC-00000000000000000000000000000000", "APP-ONE", "WF-ONE",
                "deterministic_initial_decision", DecisionType.INITIAL, DecisionOutcome.APPROVED, "CB-A", "2026.0",
                "decision-rules-v1", "DETERMINISTIC_POLICY_RULES", List.of("ALL_DETERMINISTIC_RULES_PASSED"),
                List.of(), "0123456789abcdef0123456789abcdef");
    }

    @Configuration(proxyBeanMethods = false)
    @EnableWebMvc
    @EnableWebSecurity
    @Import({ DecisionController.class, ApiExceptionHandler.class, InternalAuthorization.class, SecurityConfig.class })
    static class WebTestConfiguration {
    }
}
