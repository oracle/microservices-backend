// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.documentingest.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.cloudbank.documentingest.model.ExtractionModels.ExtractedPacket;
import com.cloudbank.documentingest.model.ExtractionModels.ExtractionResponse;
import com.cloudbank.documentingest.model.ExtractionModels.SourceDocument;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;
import org.junit.jupiter.api.Test;

class DocumentIngestServiceTest {

    private static final Path PACKET_ROOT = Path.of("..", "..", "synthetic_data", "customer_packets");

    private final DocumentIngestService service = new DocumentIngestService(new PdfTextExtractor(), new DocumentParser());

    @Test
    void readyDemoPdfsContainConsistentApplicantEmployerAndIncomeEvidence() throws Exception {
        Path packet = PACKET_ROOT.resolve("demo_geocoded_loan");
        var loan = service.extractPdf("loan_application.pdf", Files.readAllBytes(packet.resolve("loan_application.pdf")))
                .packets().getFirst();
        var pay = service.extractPdf("pay_statement_novereign_systems.pdf",
                Files.readAllBytes(packet.resolve("pay_statement_novereign_systems.pdf"))).packets().getFirst();
        assertThat(loan.getApplicationId()).isNull();
        assertThat(pay.getApplicationId()).isNull();
        assertThat(loan.getApplicant().getName()).isEqualTo(pay.getApplicant().getName());
        assertThat(loan.getEmployment().getEmployer()).isEqualTo(pay.getEmployment().getEmployer())
                .isEqualTo("Novereign Systems Cooperative");
        assertThat(loan.getIncome().getStatedGrossMonthlyIncome()).isEqualTo(pay.getIncome().getVerifiedGrossMonthlyIncome())
                .isEqualTo(7200.0);
        assertThat(loan.getLoanRequest().getRequestedAmount()).isEqualTo(5000.0);
        var manual = service.extractPdf("loan_application.pdf",
                Files.readAllBytes(packet.resolve("manual-review/loan_application.pdf"))).packets().getFirst();
        assertThat(manual.getEmployment().getEmployer()).isEqualTo("Lumenfield Analytics")
                .isNotEqualTo(pay.getEmployment().getEmployer());
    }

    @Test
    void extractsExpectedFieldsFromEachPacketUsingOnlyPdfs() throws Exception {
        Map<String, ExpectedPacket> expected = Map.of(
                "app_apr_001_elena_parker", new ExpectedPacket("APP-APR-001", "Elena Parker", "4107 Vellum Creek Pass, Orinwell, CX 49012", "Novereign Systems Cooperative", 7200.0, 7200.0, "DEBT_CONSOLIDATION", 9),
                "app_mr_002_maya_chen", new ExpectedPacket("APP-MR-002", "Maya Chen", "2208 Quartzleaf Way, Brindlewick, CX 49018", "Lumenfield Care Studio", 6400.0, 5135.0, "DEBT_CONSOLIDATION", 10),
                "app_rej_003_daniel_rojas", new ExpectedPacket("APP-REJ-003", "Daniel Rojas", "907 Emberwell Row, Caldrin, CX 49024", "Kestrel Hollow Trade Desk", 9200.0, 2100.0, "OTHER_CONSUMER_PURPOSE", 9),
                "app_opfail_004_priya_natarajan", new ExpectedPacket("APP-OPFAIL-004", "Priya Natarajan", "3182 Silverfen Mews, Asterwick, CX 49031", "Sablecrest Logistics Bureau", 7800.0, 7800.0, "HOME_IMPROVEMENT", 10),
                "app_risk_005_jordan_brooks", new ExpectedPacket("APP-RISK-005", "Jordan Brooks", "6609 North Lattice Row, Vireo Falls, CX 49042", "Copperline Ledger Works", 6200.0, 6200.0, "MAJOR_PURCHASE", 10)
        );

        for (Map.Entry<String, ExpectedPacket> entry : expected.entrySet()) {
            ExtractionResponse response = service.extract(pdfDocumentsFor(PACKET_ROOT.resolve(entry.getKey())));
            assertThat(response.packetCount()).isEqualTo(1);
            assertPacket(response.packets().getFirst(), entry.getValue());
        }
    }

    @Test
    void extractsGroupedPacketsFromZipWithoutReadingManifests() throws Exception {
        byte[] zip = zipPackets(List.of("app_apr_001_elena_parker", "app_mr_002_maya_chen"));

        ExtractionResponse response = service.extractZip(zip);

        assertThat(response.packetCount()).isEqualTo(2);
        assertThat(response.packets())
                .extracting(ExtractedPacket::getPacketId)
                .containsExactly("app_apr_001_elena_parker", "app_mr_002_maya_chen");
        assertThat(response.packets()).allSatisfy(packet -> assertThat(packet.getApplicationId()).isNull());
    }

    @Test
    void doesNotSearchForOrTrustAnApplicationIdInThePdfText() {
        ExtractedPacket packet = new ExtractedPacket("upload");

        new DocumentParser().apply("loan_application",
                List.of("Personal Loan Application", "APPLICATION ID",
                        "APP-70de9969-8889-4f71-bf3c-3ad315ee0e55"),
                packet);

        assertThat(packet.getApplicationId()).isNull();
    }

    private void assertPacket(ExtractedPacket packet, ExpectedPacket expected) {
        assertThat(packet.getApplicationId()).isNull();
        assertThat(packet.getApplicant().getName()).isEqualTo(expected.name());
        assertThat(packet.getApplicant().getAddress()).isEqualTo(expected.address());
        assertThat(packet.getEmployment().getEmployer()).isEqualTo(expected.employer());
        assertThat(packet.getIncome().getStatedGrossMonthlyIncome()).isEqualTo(expected.statedIncome());
        assertThat(packet.getIncome().getVerifiedGrossMonthlyIncome()).isEqualTo(expected.verifiedIncome());
        assertThat(packet.getLoanRequest().getPurposeCode()).isEqualTo(expected.purposeCode());
        assertThat(packet.getDocuments()).hasSize(expected.documentCount());
    }

    private List<SourceDocument> pdfDocumentsFor(Path packetDir) throws IOException {
        try (var stream = Files.list(packetDir)) {
            return stream
                    .filter(path -> path.getFileName().toString().endsWith(".pdf"))
                    .sorted()
                    .map(this::sourceDocument)
                    .toList();
        }
    }

    private SourceDocument sourceDocument(Path path) {
        try {
            return new SourceDocument(path.getFileName().toString(), Files.readAllBytes(path));
        } catch (IOException e) {
            throw new IllegalStateException(e);
        }
    }

    private byte[] zipPackets(List<String> packetSlugs) throws IOException {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        try (ZipOutputStream zip = new ZipOutputStream(buffer)) {
            for (String slug : packetSlugs) {
                for (SourceDocument document : pdfDocumentsFor(PACKET_ROOT.resolve(slug))) {
                    zip.putNextEntry(new ZipEntry(slug + "/" + document.name()));
                    zip.write(document.content());
                    zip.closeEntry();
                }
            }
        }
        return buffer.toByteArray();
    }

    private record ExpectedPacket(
            String applicationId,
            String name,
            String address,
            String employer,
            Double statedIncome,
            Double verifiedIncome,
            String purposeCode,
            int documentCount
    ) {
    }
}
