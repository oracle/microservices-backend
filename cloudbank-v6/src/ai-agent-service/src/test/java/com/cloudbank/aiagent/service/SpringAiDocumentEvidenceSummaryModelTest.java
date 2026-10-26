// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.aiagent.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.cloudbank.aiagent.config.DocumentSummaryProperties;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.ai.chat.messages.MessageType;
import org.springframework.ai.chat.model.ChatModel;
import org.springframework.ai.chat.model.ChatResponse;
import org.springframework.ai.chat.model.Generation;
import org.springframework.ai.chat.prompt.Prompt;
import org.springframework.ai.chat.prompt.ChatOptions;

class SpringAiDocumentEvidenceSummaryModelTest {
    private final ChatModel chatModel = mock(ChatModel.class);
    private final SpringAiDocumentEvidenceSummaryModel model = new SpringAiDocumentEvidenceSummaryModel(
            ChatClient.builder(chatModel), new DocumentSummaryProperties("test-model", 32, 32,
                    "Use supplied evidence only.", "Evidence: {evidence}"));

    @BeforeEach
    void configureModelOptions() {
        when(chatModel.getOptions()).thenReturn(ChatOptions.builder().build());
    }

    @Test
    void sendsConfiguredMessagesThroughSpringAiAndParsesTypedOutput() {
        when(chatModel.call(any(Prompt.class))).thenReturn(new ChatResponse(List.of(new Generation(
                new AssistantMessage("""
                        {"summary":"Evidence needs verification.","reviewNotes":["Inspect the supplied evidence."],"evidenceDocumentIds":["DOC-ONE"]}
                        """)))));
        var result = model.generate("{\"disposition\":\"MANUAL_REVIEW\"}");
        assertThat(result.summary()).isEqualTo("Evidence needs verification.");
        assertThat(result.evidenceDocumentIds()).containsExactly("DOC-ONE");
        ArgumentCaptor<Prompt> prompt = ArgumentCaptor.forClass(Prompt.class);
        verify(chatModel).call(prompt.capture());
        assertThat(prompt.getValue().getInstructions()).anySatisfy(message -> {
            assertThat(message.getMessageType()).isEqualTo(MessageType.SYSTEM);
            assertThat(message.getText()).contains("Use supplied evidence only.");
        }).anySatisfy(message -> {
            assertThat(message.getMessageType()).isEqualTo(MessageType.USER);
            assertThat(message.getText()).contains("Evidence:", "MANUAL_REVIEW");
        });
    }

    @Test
    void rejectsMalformedModelResponse() {
        when(chatModel.call(any(Prompt.class))).thenReturn(new ChatResponse(List.of(new Generation(
                new AssistantMessage("not structured JSON")))));
        assertThatThrownBy(() -> model.generate("{}"))
                .isInstanceOf(ReviewAssistanceException.class)
                .extracting(error -> ((ReviewAssistanceException) error).code()).isEqualTo("GENAI_UNAVAILABLE");
    }
}
