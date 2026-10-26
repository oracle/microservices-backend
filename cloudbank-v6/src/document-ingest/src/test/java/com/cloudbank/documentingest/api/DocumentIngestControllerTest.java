// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.documentingest.api;

import static org.hamcrest.Matchers.equalTo;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.io.ByteArrayOutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.test.context.support.WithMockUser;
import com.cloudbank.documentingest.service.DocumentIngestService;
import com.cloudbank.documentingest.service.DocumentParser;
import com.cloudbank.documentingest.service.PdfTextExtractor;

@WebMvcTest(DocumentIngestController.class)
@Import({DocumentIngestService.class, PdfTextExtractor.class, DocumentParser.class})
class DocumentIngestControllerTest {

    private static final Path APPLICATION_PDF = Path.of("..", "..", "synthetic_data", "customer_packets",
            "app_apr_001_elena_parker", "loan_application.pdf");

    @Autowired
    private MockMvc mockMvc;

    @Test
    @WithMockUser
    void healthReturnsOk() throws Exception {
        mockMvc.perform(get("/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status", equalTo("ok")));
    }

    @Test
    @WithMockUser
    void extractsSinglePdf() throws Exception {
        mockMvc.perform(post("/internal/api/v1/diagnostic-extractions/pdf-documents")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_PDF)
                        .content(Files.readAllBytes(APPLICATION_PDF)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.packetCount", equalTo(1)))
                .andExpect(jsonPath("$.packets[0].applicationId").doesNotExist())
                .andExpect(jsonPath("$.packets[0].applicant.name", equalTo("Elena Parker")));
    }

    @Test
    @WithMockUser
    void extractsZipArchive() throws Exception {
        byte[] pdf = Files.readAllBytes(APPLICATION_PDF);
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        try (ZipOutputStream zip = new ZipOutputStream(buffer)) {
            zip.putNextEntry(new ZipEntry("app_apr_001_elena_parker/loan_application.pdf"));
            zip.write(pdf);
            zip.closeEntry();
        }

        mockMvc.perform(post("/internal/api/v1/diagnostic-extractions/zip-archives")
                        .with(csrf())
                        .contentType("application/zip")
                        .content(buffer.toByteArray()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.packetCount", equalTo(1)))
                .andExpect(jsonPath("$.packets[0].applicationId").doesNotExist());
    }

    @Test
    @WithMockUser
    void extractsMultipartFileBatch() throws Exception {
        MockMultipartFile file = new MockMultipartFile("files", "loan_application.pdf",
                MediaType.APPLICATION_PDF_VALUE, Files.readAllBytes(APPLICATION_PDF));

        mockMvc.perform(multipart("/internal/api/v1/diagnostic-extractions/file-batches")
                        .file(file)
                        .with(csrf()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.packetCount", equalTo(1)))
                .andExpect(jsonPath("$.packets[0].applicationId").doesNotExist());
    }
}
