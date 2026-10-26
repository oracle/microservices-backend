// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.documentingest.api;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.cloudbank.documentingest.model.WorkflowExtractionModels.WorkflowExtractionRequest;
import com.cloudbank.documentingest.model.WorkflowExtractionModels.WorkflowExtractionResponse;
import com.cloudbank.documentingest.service.WorkflowExtractionService;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.http.HttpStatus;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.server.ResponseStatusException;

@WebMvcTest(WorkflowExtractionController.class)
class WorkflowExtractionControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private WorkflowExtractionService service;

    @Test
    @WithMockUser
    void startsWorkflowManagedDocumentExtraction() throws Exception {
        when(service.extract(any(WorkflowExtractionRequest.class), eq("workflow-task-001")))
                .thenReturn(new WorkflowExtractionResponse(
                        "APP-TEST", "workflow-001", "extract-documents", List.of()));

        mockMvc.perform(post("/internal/api/v1/document-extractions")
                        .with(csrf())
                        .header("Idempotency-Key", "workflow-task-001")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "applicationId": "APP-TEST",
                                  "workflowId": "workflow-001",
                                  "taskReference": "extract-documents",
                                  "traceId": "0123456789abcdef0123456789abcdef"
                                }
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.applicationId").value("APP-TEST"))
                .andExpect(jsonPath("$.workflowId").value("workflow-001"));

        verify(service).extract(any(WorkflowExtractionRequest.class), eq("workflow-task-001"));
    }

    @Test
    @WithMockUser
    void returnsServerErrorWhenNoDocumentsAreProcessable() throws Exception {
        when(service.extract(any(WorkflowExtractionRequest.class), eq("workflow-task-002")))
                .thenThrow(new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                        "No processable documents were found for the application"));

        mockMvc.perform(post("/internal/api/v1/document-extractions")
                        .with(csrf())
                        .header("Idempotency-Key", "workflow-task-002")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "applicationId": "APP-TEST",
                                  "workflowId": "workflow-001",
                                  "taskReference": "extract-documents",
                                  "traceId": "0123456789abcdef0123456789abcdef"
                                }
                                """))
                .andExpect(status().isServiceUnavailable());
    }
}
