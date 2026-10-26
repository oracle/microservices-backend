// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentreview.client;

import static org.springframework.security.oauth2.client.web.client.RequestAttributeClientRegistrationIdResolver.clientRegistrationId;
import static org.springframework.security.oauth2.client.web.client.RequestAttributePrincipalResolver.principal;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientManager;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientService;
import org.springframework.security.oauth2.client.web.client.OAuth2ClientHttpRequestInterceptor;
import org.springframework.security.oauth2.client.web.client.RequestAttributePrincipalResolver;
import org.springframework.web.client.RestClient;

final class AuthenticatedRestClientFactory {
    private AuthenticatedRestClientFactory() {
    }

    static RestClient create(RestClient.Builder builder, OAuth2AuthorizedClientManager manager,
            OAuth2AuthorizedClientService service, String baseUrl) {
        OAuth2ClientHttpRequestInterceptor oauth2 = new OAuth2ClientHttpRequestInterceptor(manager);
        oauth2.setPrincipalResolver(new RequestAttributePrincipalResolver());
        oauth2.setAuthorizationFailureHandler(OAuth2ClientHttpRequestInterceptor.authorizationFailureHandler(service));
        return builder.baseUrl(baseUrl).defaultRequest(request -> request
                .attributes(clientRegistrationId("cloudbank-service")).attributes(principal("document-review-service")))
                .requestInterceptor(oauth2).build();
    }
}
