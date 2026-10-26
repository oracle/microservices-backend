// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.documentingest.api;

import com.cloudbank.documentingest.model.ExtractionModels.ExtractionResponse;
import com.cloudbank.documentingest.service.DocumentIngestService;
import java.io.IOException;
import org.springframework.http.MediaType;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
public class DocumentIngestController {

    private final DocumentIngestService ingestService;

    public DocumentIngestController(DocumentIngestService ingestService) {
        this.ingestService = ingestService;
    }

    @GetMapping("/health")
    public HealthResponse health() {
        return new HealthResponse("ok", "cloudbank-document-ingest");
    }

    @PostMapping(path = "/internal/api/v1/diagnostic-extractions/pdf-documents",
            consumes = MediaType.APPLICATION_PDF_VALUE)
    @PreAuthorize("@documentIngestAuthorization.isInternal(authentication)")
    public ExtractionResponse extractPdf(@RequestBody byte[] pdf) throws IOException {
        return ingestService.extractPdf("upload.pdf", pdf);
    }

    @PostMapping(path = "/internal/api/v1/diagnostic-extractions/zip-archives",
            consumes = "application/zip")
    @PreAuthorize("@documentIngestAuthorization.isInternal(authentication)")
    public ExtractionResponse extractZip(@RequestBody byte[] zip) throws IOException {
        return ingestService.extractZip(zip);
    }

    @PostMapping(path = "/internal/api/v1/diagnostic-extractions/file-batches",
            consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @PreAuthorize("@documentIngestAuthorization.isInternal(authentication)")
    public ExtractionResponse extractMultipart(@RequestPart("files") MultipartFile[] files) throws IOException {
        return ingestService.extractMultipart(files);
    }

    public record HealthResponse(String status, String service) {
    }
}
