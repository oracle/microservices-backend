// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.gatewaybff;

import jakarta.servlet.http.HttpServletRequest;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.security.core.Authentication;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;

class BffControllerTest {
    @Test
    void listsWithUserTokenAndDropsInternalWorkflowErrors() {
        SessionIdentity identity = mock(SessionIdentity.class);
        Authentication authentication = mock(Authentication.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        when(identity.require(eq(authentication), any(HttpServletRequest.class)))
                .thenReturn(new SessionIdentity.AuthorizedUser("obaas-admin", "server-held-token", null));
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer upstream = MockRestServiceServer.bindTo(builder).build();
        upstream.expect(requestTo("http://loan.example/api/v1/loan-applications?page=0&size=20&scenarioId=SCN-1"))
                .andExpect(header("Authorization", "Bearer server-held-token"))
                .andRespond(withSuccess("""
                        {"content":[{"applicationId":"APP-1","scenarioId":"SCN-1",
                        "scenarioName":"Synthetic Case","status":"SUBMITTED",
                        "requestedAmount":12000.00,"requestedTermMonths":36,
                        "createdAt":"2026-10-14T10:00:00Z","updatedAt":"2026-10-14T10:01:00Z",
                        "workflow":{"workflowId":"WF-1","lastErrorMessage":"internal detail"},
                        "traceId":"TRACE-1","documents":[{"fileName":"private.pdf"}]}],
                        "page":{"number":0,"size":20,"totalElements":1,"totalPages":1}}
                        """, MediaType.APPLICATION_JSON));

        BffController.ApplicationPage page = new BffController(identity, "http://loan.example", builder)
                .applications(null, "SCN-1", 0, 20, authentication, request);

        upstream.verify();
        assertThat(page.content()).hasSize(1);
        assertThat(page.content().getFirst().workflowId()).isEqualTo("WF-1");
        assertThat(page.content().getFirst().toString()).doesNotContain("internal detail", "private.pdf");
        assertThat(page.page().totalElements()).isEqualTo(1);
    }

    @Test
    void upstreamUnauthorizedDoesNotClaimTheBrowserSessionExpired() {
        SessionIdentity identity = mock(SessionIdentity.class);
        Authentication authentication = mock(Authentication.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        when(identity.require(eq(authentication), any(HttpServletRequest.class)))
                .thenReturn(new SessionIdentity.AuthorizedUser("obaas-admin", "server-held-token", null));
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer upstream = MockRestServiceServer.bindTo(builder).build();
        upstream.expect(requestTo("http://loan.example/api/v1/loan-applications?page=0&size=20"))
                .andRespond(withStatus(HttpStatus.UNAUTHORIZED));

        BffController controller = new BffController(identity, "http://loan.example", builder);
        assertThatThrownBy(() -> controller.applications(null, null, 0, 20, authentication, request))
                .isInstanceOfSatisfying(ResponseStatusException.class,
                        error -> assertThat(error.getStatusCode()).isEqualTo(HttpStatus.BAD_GATEWAY));
        upstream.verify();
    }
}
