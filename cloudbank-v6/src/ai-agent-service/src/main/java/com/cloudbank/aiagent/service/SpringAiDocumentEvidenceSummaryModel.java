// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.aiagent.service;

import com.cloudbank.aiagent.config.DocumentSummaryProperties;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.stereotype.Component;

@Component
public class SpringAiDocumentEvidenceSummaryModel implements DocumentEvidenceSummaryModel {
    private final ChatClient chatClient;
    private final DocumentSummaryProperties properties;

    public SpringAiDocumentEvidenceSummaryModel(ChatClient.Builder builder, DocumentSummaryProperties properties) {
        this.chatClient = builder.build();
        this.properties = properties;
    }

    @Override
    public DocumentSummaryModelOutput generate(String evidenceJson) {
        try {
            return chatClient.prompt().system(properties.systemPrompt())
                    .user(user -> user.text(properties.evidencePrompt()).param("evidence", evidenceJson))
                    .call().entity(DocumentSummaryModelOutput.class, spec -> spec.validateSchema());
        } catch (RuntimeException exception) {
            throw ReviewAssistanceException.modelUnavailable(exception);
        }
    }
}
