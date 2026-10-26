// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyloader;

import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static com.cloudbank.policyloader.PolicyCorpusModels.Corpus;
import static com.cloudbank.policyloader.PolicyCorpusModels.ManifestDocument;
import static com.cloudbank.policyloader.PolicyCorpusModels.PolicyChunk;
import static com.cloudbank.policyloader.PolicyCorpusModels.PolicyDocument;

@Component
class PolicyCorpusReader {
    private static final String MANIFEST_FILE = "policy_corpus_manifest.json";
    private static final Pattern TITLE = Pattern.compile("(?m)^#\\s+(.+?)\\s*$");
    private static final Pattern SECTION = Pattern.compile("(?m)^##\\s+(S\\d+)\\.\\s+(.+?)\\s*$");
    private static final Pattern POLICY_ID = Pattern.compile("\\*\\*Policy ID:\\*\\*\\s*`?([^`\\s]+)");
    private static final Pattern VERSION = Pattern.compile("\\*\\*Version:\\*\\*\\s*([^\\s]+)");
    private static final Pattern EFFECTIVE_DATE = Pattern.compile("\\*\\*Effective date:\\*\\*\\s*(\\d{4}-\\d{2}-\\d{2})");
    private static final Pattern DEFAULT_ROLES = Pattern.compile("\\*\\*Default access roles:\\*\\*\\s*(.*)");
    private static final Pattern LOAN_OFFICER_SECTIONS = Pattern.compile("\\*\\*Loan-officer accessible sections:\\*\\*\\s*(.*)");
    private static final Pattern UNDERWRITER_SECTIONS = Pattern.compile("\\*\\*Underwriter-only sections:\\*\\*\\s*(.*)");
    private static final Pattern POLICY_DOMAIN = Pattern.compile("\\*\\*Policy domain:\\*\\*\\s*(.*)");

    private final ObjectMapper json;

    PolicyCorpusReader(ObjectMapper json) {
        this.json = json;
    }

    Corpus read(Path configuredPath) {
        Path root = configuredPath.toAbsolutePath().normalize();
        Path manifestPath = root.resolve(MANIFEST_FILE);
        try {
            byte[] manifestBytes = Files.readAllBytes(manifestPath);
            JsonNode manifest = json.readTree(manifestBytes);
            String corpusId = requiredText(manifest, "corpusId");
            String version = requiredText(manifest, "version");
            JsonNode documentNodes = manifest.get("documents");
            if (documentNodes == null || !documentNodes.isArray() || documentNodes.isEmpty()) {
                throw new IllegalArgumentException("policy corpus manifest must declare at least one document");
            }

            List<ManifestDocument> entries = new ArrayList<>();
            Set<String> files = new HashSet<>();
            Set<String> policyIds = new HashSet<>();
            for (JsonNode node : documentNodes) {
                ManifestDocument entry = new ManifestDocument(requiredText(node, "file"),
                        requiredText(node, "policyId"), requiredText(node, "title"), requiredText(node, "domain"));
                if (!entry.file().matches("[A-Za-z0-9][A-Za-z0-9._-]*\\.md")) {
                    throw new IllegalArgumentException("manifest contains an unsafe policy filename");
                }
                if (!files.add(entry.file()) || !policyIds.add(entry.policyId())) {
                    throw new IllegalArgumentException("manifest contains duplicate policy files or IDs");
                }
                entries.add(entry);
            }

            MessageDigest digest = sha256();
            digest.update(manifestBytes);
            List<PolicyDocument> documents = new ArrayList<>();
            for (ManifestDocument entry : entries) {
                Path file = root.resolve(entry.file()).normalize();
                if (!file.getParent().equals(root) || !Files.isRegularFile(file)) {
                    throw new IllegalArgumentException("manifest policy file is missing or outside the corpus directory");
                }
                byte[] markdown = Files.readAllBytes(file);
                digest.update(entry.file().getBytes(StandardCharsets.UTF_8));
                digest.update((byte) 0);
                digest.update(markdown);
                documents.add(parse(entry, version, markdown));
            }
            return new Corpus(corpusId, version, HexFormat.of().formatHex(digest.digest()), List.copyOf(documents));
        }
        catch (JacksonException exception) {
            throw new IllegalArgumentException("policy corpus manifest is not valid JSON", exception);
        }
        catch (IOException exception) {
            throw new IllegalStateException("policy corpus could not be read", exception);
        }
    }

    private static PolicyDocument parse(ManifestDocument manifest, String corpusVersion, byte[] markdown) {
        String source = new String(markdown, StandardCharsets.UTF_8);
        String policyId = value(source, POLICY_ID, null);
        if (!manifest.policyId().equals(policyId)) {
            throw new IllegalArgumentException("policy ID does not match the corpus manifest for " + manifest.file());
        }
        String title = first(source, TITLE, null);
        String version = value(source, VERSION, corpusVersion);
        if (!corpusVersion.equals(version)) {
            throw new IllegalArgumentException("policy version does not match the corpus version for " + manifest.file());
        }
        LocalDate effectiveDate = LocalDate.parse(value(source, EFFECTIVE_DATE, null));
        String defaultRoles = value(source, DEFAULT_ROLES, "LOAN_OFFICER, UNDERWRITER");
        Set<String> loanOfficerSections = listValue(source, LOAN_OFFICER_SECTIONS);
        Set<String> underwriterSections = listValue(source, UNDERWRITER_SECTIONS);
        String domain = value(source, POLICY_DOMAIN, manifest.domain());

        Matcher matcher = SECTION.matcher(source);
        List<SectionMatch> sectionMatches = new ArrayList<>();
        while (matcher.find()) {
            sectionMatches.add(new SectionMatch(matcher.group(1), matcher.group(2).trim(), matcher.start(), matcher.end()));
        }
        if (sectionMatches.isEmpty()) {
            throw new IllegalArgumentException("policy document contains no numbered sections: " + manifest.file());
        }

        List<PolicyChunk> chunks = new ArrayList<>();
        for (int index = 0; index < sectionMatches.size(); index++) {
            SectionMatch section = sectionMatches.get(index);
            int bodyEnd = index + 1 < sectionMatches.size() ? sectionMatches.get(index + 1).start() : source.length();
            String text = source.substring(section.end(), bodyEnd).trim();
            if (text.isEmpty()) {
                throw new IllegalArgumentException("policy section is empty: " + policyId + "-" + section.reference());
            }
            String minRole = underwriterSections.contains(section.reference())
                    || !(loanOfficerSections.contains(section.reference()) || defaultRoles.contains("LOAN_OFFICER"))
                    ? "UNDERWRITER" : "LOAN_OFFICER";
            chunks.add(new PolicyChunk(policyId + "-" + section.reference() + "-C01", section.reference(),
                    section.reference() + ". " + section.heading(), index + 1, text, minRole));
        }
        return new PolicyDocument(policyId, policyId, title, version,
                "synthetic_data/policy/" + manifest.file(), effectiveDate, domain, List.copyOf(chunks));
    }

    private static String requiredText(JsonNode node, String field) {
        JsonNode value = node.get(field);
        if (value == null || !value.isTextual() || value.asText().isBlank()) {
            throw new IllegalArgumentException("policy corpus manifest field is missing or empty: " + field);
        }
        return value.asText();
    }

    private static String value(String source, Pattern pattern, String fallback) {
        Matcher matcher = pattern.matcher(source);
        if (matcher.find()) {
            return matcher.group(1).replace("`", "").trim();
        }
        if (fallback == null) {
            throw new IllegalArgumentException("required policy metadata is missing");
        }
        return fallback;
    }

    private static String first(String source, Pattern pattern, String fallback) {
        Matcher matcher = pattern.matcher(source);
        if (matcher.find()) {
            return matcher.group(1).trim();
        }
        if (fallback == null) {
            throw new IllegalArgumentException("policy title is missing");
        }
        return fallback;
    }

    private static Set<String> listValue(String source, Pattern pattern) {
        Set<String> sections = new HashSet<>();
        Matcher matcher = Pattern.compile("S\\d+").matcher(value(source, pattern, ""));
        while (matcher.find()) {
            sections.add(matcher.group());
        }
        return sections;
    }

    private static MessageDigest sha256() {
        try {
            return MessageDigest.getInstance("SHA-256");
        }
        catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }

    private record SectionMatch(String reference, String heading, int start, int end) {
    }
}
