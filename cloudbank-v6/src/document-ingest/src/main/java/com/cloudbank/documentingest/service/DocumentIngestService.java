// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.documentingest.service;

import com.cloudbank.documentingest.model.ExtractionModels.DocumentSummary;
import com.cloudbank.documentingest.model.ExtractionModels.ExtractedPacket;
import com.cloudbank.documentingest.model.ExtractionModels.ExtractionResponse;
import com.cloudbank.documentingest.model.ExtractionModels.SourceDocument;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

@Service
public class DocumentIngestService {

    static final String SERVICE_NAME = "cloudbank-document-ingest";
    static final String PROVIDER = "local_pdf_text";

    private final PdfTextExtractor pdfTextExtractor;
    private final DocumentParser documentParser;

    public DocumentIngestService(PdfTextExtractor pdfTextExtractor, DocumentParser documentParser) {
        this.pdfTextExtractor = pdfTextExtractor;
        this.documentParser = documentParser;
    }

    public ExtractionResponse extractPdf(String fileName, byte[] content) throws IOException {
        return extract(List.of(new SourceDocument(fileName, content)));
    }

    public ExtractionResponse extractZip(byte[] zipContent) throws IOException {
        return extract(documentsFromZip(zipContent));
    }

    public ExtractionResponse extractMultipart(MultipartFile[] files) throws IOException {
        List<SourceDocument> documents = new ArrayList<>();
        for (MultipartFile file : files) {
            String fileName = file.getOriginalFilename() == null ? "upload.pdf" : file.getOriginalFilename();
            if (fileName.toLowerCase().endsWith(".zip")) {
                documents.addAll(documentsFromZip(file.getBytes()));
            } else {
                documents.add(new SourceDocument(fileName, file.getBytes()));
            }
        }
        return extract(documents);
    }

    public ExtractionResponse extract(List<SourceDocument> documents) throws IOException {
        Map<String, List<SourceDocument>> groups = group(documents);
        List<ExtractedPacket> packets = new ArrayList<>();
        for (Map.Entry<String, List<SourceDocument>> entry : groups.entrySet()) {
            packets.add(extractPacket(entry.getKey(), entry.getValue()));
        }
        return new ExtractionResponse(SERVICE_NAME, PROVIDER, packets.size(), packets);
    }

    private ExtractedPacket extractPacket(String packetId, List<SourceDocument> documents) throws IOException {
        ExtractedPacket packet = new ExtractedPacket(packetId);
        List<SourceDocument> sorted = documents.stream()
                .sorted(Comparator.comparing(SourceDocument::name))
                .toList();
        for (SourceDocument document : sorted) {
            if (!document.name().toLowerCase().endsWith(".pdf")) {
                packet.getWarnings().add("skipped_non_pdf:" + document.name());
                continue;
            }
            List<String> lines = pdfTextExtractor.extractLines(document.content());
            String type = documentParser.classify(document.name(), lines);
            packet.getDocuments().add(new DocumentSummary(document.name(), type, lines.size()));
            documentParser.apply(type, lines, packet);
        }
        if (packet.getIncome().getVerifiedGrossMonthlyIncome() == null) {
            packet.getIncome().setVerifiedGrossMonthlyIncome(packet.getIncome().getPayStatementMonthlyGross());
        }
        dedupe(packet);
        return packet;
    }

    private List<SourceDocument> documentsFromZip(byte[] zipContent) throws IOException {
        List<SourceDocument> documents = new ArrayList<>();
        try (ZipInputStream zip = new ZipInputStream(new ByteArrayInputStream(zipContent))) {
            ZipEntry entry;
            while ((entry = zip.getNextEntry()) != null) {
                if (entry.isDirectory() || !entry.getName().toLowerCase().endsWith(".pdf")) {
                    continue;
                }
                documents.add(new SourceDocument(entry.getName(), zip.readAllBytes()));
            }
        }
        return documents;
    }

    private Map<String, List<SourceDocument>> group(List<SourceDocument> documents) {
        Map<String, List<SourceDocument>> groups = new LinkedHashMap<>();
        for (SourceDocument document : documents) {
            String normalized = document.name().replace('\\', '/');
            int slash = normalized.indexOf('/');
            String packetId = slash > 0 ? normalized.substring(0, slash) : "upload";
            groups.computeIfAbsent(packetId, ignored -> new ArrayList<>()).add(document);
        }
        return groups;
    }

    private void dedupe(ExtractedPacket packet) {
        packet.getValidationSignals().clear();
        packet.getValidationSignals().addAll(new TreeSet<>(packet.getValidationSignals()));
        packet.getWarnings().clear();
        packet.getWarnings().addAll(new TreeSet<>(packet.getWarnings()));
    }
}
