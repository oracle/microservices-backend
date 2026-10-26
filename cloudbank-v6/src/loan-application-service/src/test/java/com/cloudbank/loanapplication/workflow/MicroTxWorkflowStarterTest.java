// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.workflow;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.content;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.queryParam;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import com.cloudbank.loanapplication.workflow.WorkflowStarter.StartWorkflowCommand;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

class MicroTxWorkflowStarterTest {

    @Test
    void rejectsMicroTxModeWithoutTokenConfiguration() {
        RestClient.Builder builder = RestClient.builder();

        assertThatThrownBy(() -> new MicroTxWorkflowStarter(builder, new ObjectMapper(), "http://microtx.example", "",
                "", "", "", "", "", "", "")).isInstanceOf(IllegalStateException.class)
                        .hasMessageContaining("requires token URI, client ID, client secret, and scope");
    }

    @Test
    void injectsShortLivedServiceTokenIntoWorkflowInputForDocumentIngest() {
        RestClient.Builder workflowBuilder = RestClient.builder();
        MockRestServiceServer workflowServer = MockRestServiceServer.bindTo(workflowBuilder).build();
        RestClient.Builder tokenBuilder = RestClient.builder();
        MockRestServiceServer tokenServer = MockRestServiceServer.bindTo(tokenBuilder).build();
        MicroTxWorkflowStarter starter = new MicroTxWorkflowStarter(
                workflowBuilder.baseUrl("http://microtx.example").build(), tokenBuilder.build(), new ObjectMapper(),
                new MicroTxWorkflowStarter.OAuthClient("http://azn.example/oauth2/token", "microtx-workflow-client",
                        "MicroTxClientSecret123!", "microtx.workflow"),
                new MicroTxWorkflowStarter.OAuthClient("http://azn.example/oauth2/token", "cloudbank-service-client",
                        "ServiceClientSecret123!", "cloudbank.internal"));
        String payload = """
                {
                  "applicationId": "APP-12345678-1234-1234-1234-123456789abc",
                  "traceId": "0123456789abcdef0123456789abcdef",
                  "scenarioId": "SMOKE-20260629T180000Z",
                  "scenarioName": "Loan Intake Smoke Test",
                  "documentCount": 2
                }
                """;
        String expectedWorkflowInput = """
                {
                  "applicationId": "APP-12345678-1234-1234-1234-123456789abc",
                  "traceId": "0123456789abcdef0123456789abcdef",
                  "scenarioId": "SMOKE-20260629T180000Z",
                  "scenarioName": "Loan Intake Smoke Test",
                  "documentCount": 2,
                  "workflowTaskAuthorization": "Bearer service-token-123"
                }
                """;
        String microtxBasic = Base64.getEncoder()
                .encodeToString("microtx-workflow-client:MicroTxClientSecret123!".getBytes(StandardCharsets.UTF_8));
        String serviceBasic = Base64.getEncoder()
                .encodeToString("cloudbank-service-client:ServiceClientSecret123!".getBytes(StandardCharsets.UTF_8));

        tokenServer.expect(requestTo("http://azn.example/oauth2/token")).andExpect(method(HttpMethod.POST))
                .andExpect(header("Authorization", "Basic " + microtxBasic))
                .andExpect(content().contentType(MediaType.APPLICATION_FORM_URLENCODED))
                .andExpect(content().string("grant_type=client_credentials&scope=microtx.workflow"))
                .andRespond(withSuccess("{\"access_token\":\"microtx-token-123\"}", MediaType.APPLICATION_JSON));
        tokenServer.expect(requestTo("http://azn.example/oauth2/token")).andExpect(method(HttpMethod.POST))
                .andExpect(header("Authorization", "Basic " + serviceBasic))
                .andExpect(content().contentType(MediaType.APPLICATION_FORM_URLENCODED))
                .andExpect(content().string("grant_type=client_credentials&scope=cloudbank.internal"))
                .andRespond(withSuccess("{\"access_token\":\"service-token-123\"}", MediaType.APPLICATION_JSON));
        workflowServer
                .expect(requestTo("http://microtx.example/api/workflow/cloudbank-loan-origination"
                        + "?version=1&correlationId=APP-12345678-1234-1234-1234-123456789abc"
                        + "&idempotencyKey=APP-12345678-1234-1234-1234-123456789abc"))
                .andExpect(method(HttpMethod.POST)).andExpect(header("Authorization", "Bearer microtx-token-123"))
                .andExpect(header("traceparent", "00-0123456789abcdef0123456789abcdef-0000000000000001-01"))
                .andExpect(content().json(expectedWorkflowInput))
                .andRespond(withSuccess("\"workflow-001\"", MediaType.APPLICATION_JSON));

        var execution = starter.start(
                new StartWorkflowCommand("cloudbank-loan-origination", 1, "APP-12345678-1234-1234-1234-123456789abc",
                        "APP-12345678-1234-1234-1234-123456789abc", payload, "0123456789abcdef0123456789abcdef"));

        assertThat(execution.workflowId()).isEqualTo("workflow-001");
        tokenServer.verify();
        workflowServer.verify();
    }

    @Test
    void reportsMicrotxTokenFailureBeforeRequestingTaskToken() {
        RestClient.Builder tokenBuilder = RestClient.builder();
        MockRestServiceServer tokenServer = MockRestServiceServer.bindTo(tokenBuilder).build();
        MicroTxWorkflowStarter starter = starter(tokenBuilder.build());

        tokenServer.expect(requestTo("http://azn.example/oauth2/token"))
                .andExpect(content().string("grant_type=client_credentials&scope=microtx.workflow"))
                .andRespond(withSuccess("{}", MediaType.APPLICATION_JSON));

        assertThatThrownBy(() -> starter.start(command())).isInstanceOfSatisfying(
                MicroTxWorkflowStarter.WorkflowStartException.class,
                exception -> assertThat(exception.code()).isEqualTo("MICROTX_TOKEN_FAILURE"));
        tokenServer.verify();
    }

    @Test
    void reportsWorkflowTaskTokenFailureSeparately() {
        RestClient.Builder tokenBuilder = RestClient.builder();
        MockRestServiceServer tokenServer = MockRestServiceServer.bindTo(tokenBuilder).build();
        MicroTxWorkflowStarter starter = starter(tokenBuilder.build());

        tokenServer.expect(requestTo("http://azn.example/oauth2/token"))
                .andExpect(content().string("grant_type=client_credentials&scope=microtx.workflow"))
                .andRespond(withSuccess("{\"access_token\":\"microtx-token-123\"}", MediaType.APPLICATION_JSON));
        tokenServer.expect(requestTo("http://azn.example/oauth2/token"))
                .andExpect(content().string("grant_type=client_credentials&scope=cloudbank.internal"))
                .andRespond(withSuccess("{}", MediaType.APPLICATION_JSON));

        assertThatThrownBy(() -> starter.start(command())).isInstanceOfSatisfying(
                MicroTxWorkflowStarter.WorkflowStartException.class,
                exception -> assertThat(exception.code()).isEqualTo("WORKFLOW_TASK_TOKEN_FAILURE"));
        tokenServer.verify();
    }

    @Test
    void warmsTheDefinitionCacheAndRetriesAWorkflowTemporarilyMissingAfterDeployment() {
        RestClient.Builder workflowBuilder = RestClient.builder();
        MockRestServiceServer workflowServer = MockRestServiceServer.bindTo(workflowBuilder).build();
        RestClient.Builder tokenBuilder = RestClient.builder();
        MockRestServiceServer tokenServer = MockRestServiceServer.bindTo(tokenBuilder).build();
        MicroTxWorkflowStarter starter = new MicroTxWorkflowStarter(
                workflowBuilder.baseUrl("http://microtx.example").build(), tokenBuilder.build(), new ObjectMapper(),
                new MicroTxWorkflowStarter.OAuthClient("http://azn.example/oauth2/token", "microtx-workflow-client",
                        "MicroTxClientSecret123!", "microtx.workflow"),
                new MicroTxWorkflowStarter.OAuthClient("http://azn.example/oauth2/token", "cloudbank-service-client",
                        "ServiceClientSecret123!", "cloudbank.internal"));

        tokenServer.expect(requestTo("http://azn.example/oauth2/token"))
                .andRespond(withSuccess("{\"access_token\":\"microtx-token-123\"}", MediaType.APPLICATION_JSON));
        tokenServer.expect(requestTo("http://azn.example/oauth2/token"))
                .andRespond(withSuccess("{\"access_token\":\"service-token-123\"}", MediaType.APPLICATION_JSON));
        workflowServer.expect(requestTo("http://microtx.example/api/workflow/cloudbank-loan-origination"
                        + "?version=1&correlationId=APP-12345678-1234-1234-1234-123456789abc"
                        + "&idempotencyKey=APP-12345678-1234-1234-1234-123456789abc"))
                .andRespond(withStatus(HttpStatus.NOT_FOUND).contentType(MediaType.APPLICATION_JSON)
                        .body("{\"message\":\"No such workflow found\"}"));
        workflowServer.expect(requestTo("http://microtx.example/api/metadata/workflow/cloudbank-loan-origination"
                        + "?version=1"))
                .andExpect(method(HttpMethod.GET))
                .andExpect(header("Authorization", "Bearer microtx-token-123"))
                .andRespond(withSuccess("{\"name\":\"cloudbank-loan-origination\",\"version\":1}",
                        MediaType.APPLICATION_JSON));
        workflowServer.expect(requestTo("http://microtx.example/api/workflow/cloudbank-loan-origination"
                        + "?version=1&correlationId=APP-12345678-1234-1234-1234-123456789abc"
                        + "&idempotencyKey=APP-12345678-1234-1234-1234-123456789abc"))
                .andRespond(withSuccess("\"workflow-001\"", MediaType.APPLICATION_JSON));

        assertThat(starter.start(command()).workflowId()).isEqualTo("workflow-001");
        tokenServer.verify();
        workflowServer.verify();
    }

    private static MicroTxWorkflowStarter starter(RestClient tokenClient) {
        return new MicroTxWorkflowStarter(RestClient.create("http://microtx.example"), tokenClient, new ObjectMapper(),
                new MicroTxWorkflowStarter.OAuthClient("http://azn.example/oauth2/token", "microtx-workflow-client",
                        "MicroTxClientSecret123!", "microtx.workflow"),
                new MicroTxWorkflowStarter.OAuthClient("http://azn.example/oauth2/token", "cloudbank-service-client",
                        "ServiceClientSecret123!", "cloudbank.internal"));
    }

    private static StartWorkflowCommand command() {
        return new StartWorkflowCommand("cloudbank-loan-origination", 1, "APP-12345678-1234-1234-1234-123456789abc",
                "APP-12345678-1234-1234-1234-123456789abc",
                "{\"applicationId\":\"APP-12345678-1234-1234-1234-123456789abc\"}", "0123456789abcdef0123456789abcdef");
    }
}
