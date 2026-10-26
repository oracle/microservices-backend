// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.documentingest.service;

import java.io.IOException;
import java.util.Arrays;
import java.util.List;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.text.PDFTextStripper;
import org.springframework.stereotype.Component;

@Component
public class PdfTextExtractor {

    public List<String> extractLines(byte[] pdfContent) throws IOException {
        try (PDDocument document = Loader.loadPDF(pdfContent)) {
            PDFTextStripper stripper = new PDFTextStripper();
            String text = stripper.getText(document);
            return Arrays.stream(text.split("\\R"))
                    .map(String::trim)
                    .filter(line -> !line.isBlank())
                    .toList();
        }
    }
}
