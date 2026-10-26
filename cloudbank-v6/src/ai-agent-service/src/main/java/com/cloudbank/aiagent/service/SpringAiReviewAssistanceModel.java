// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.aiagent.service;

import com.cloudbank.aiagent.config.ReviewAssistanceProperties;
import java.util.List;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.stereotype.Component;

@Component
public class SpringAiReviewAssistanceModel {
    private final ChatClient chatClient;
    private final ReviewAssistanceProperties properties;

    public SpringAiReviewAssistanceModel(ChatClient.Builder builder, ReviewAssistanceProperties properties) {
        this.chatClient = builder.build();
        this.properties = properties;
    }

    public ReviewAssistanceModelOutput generate(String evidenceJson) {
        try {
            return chatClient.prompt().system(properties.systemPrompt())
                    .user(user -> user.text(properties.evidencePrompt()).param("evidence", evidenceJson))
                    .call().entity(ReviewAssistanceModelOutput.class, spec -> spec.validateSchema());
        } catch (RuntimeException exception) {
            throw ReviewAssistanceException.modelUnavailable(exception);
        }
    }

    public record ReviewAssistanceModelOutput(List<String> checklist, List<String> clarificationQuestions) {
    }
}
