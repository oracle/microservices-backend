// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.documentingest.service;

import com.cloudbank.documentingest.model.ExtractionModels.ExtractedPacket;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.springframework.stereotype.Component;

@Component
public class DocumentParser {

    private static final Pattern MONEY = Pattern.compile("-?\\$?([0-9][0-9,]*(?:\\.[0-9]{2})?)");
    private static final Pattern TERM = Pattern.compile("(\\d+)\\s*months?", Pattern.CASE_INSENSITIVE);

    public String classify(String fileName, List<String> lines) {
        String text = String.join("\n", lines).toLowerCase(Locale.ROOT);
        String base = fileName.toLowerCase(Locale.ROOT);
        if (text.contains("personal loan application") || base.equals("loan_application.pdf")) {
            return "loan_application";
        }
        if (text.contains("identity verification summary")) {
            return "identity_verification_summary";
        }
        if (text.contains("account activity summary") || base.contains("deposit_summary")) {
            return "account_activity_summary";
        }
        if (text.contains("liability schedule")) {
            return "liability_schedule";
        }
        if (text.contains("clarification request")) {
            return "income_clarification_request";
        }
        if (text.contains("document receipt")) {
            return "document_receipt";
        }
        if (text.contains("relationship signal summary")) {
            return "relationship_signal_summary";
        }
        if (text.contains("contractor income statement")) {
            return "contractor_income_statement";
        }
        if (text.contains("pay statement") || text.contains("earnings statement")
                || text.contains("payroll advice") || text.contains("earnings record")) {
            return "pay_statement";
        }
        return "unknown";
    }

    public void apply(String documentType, List<String> lines, ExtractedPacket packet) {
        switch (documentType) {
            case "loan_application" -> parseLoanApplication(lines, packet);
            case "identity_verification_summary" -> parseIdentitySummary(lines, packet);
            case "pay_statement" -> parsePayStatement(lines, packet);
            case "account_activity_summary" -> parseAccountActivity(lines, packet);
            case "liability_schedule" -> parseLiabilitySchedule(lines, packet);
            case "contractor_income_statement" -> parseContractorIncome(lines, packet);
            default -> {
            }
        }
        packet.getValidationSignals().addAll(parseSignals(documentType, lines));
    }

    private void parseLoanApplication(List<String> lines, ExtractedPacket packet) {
        setIfMissing(packet.getApplicant()::setApplicantId, packet.getApplicant().getApplicantId(), valueAfter(lines, "APPLICANT ID"));
        setIfMissing(packet.getApplicant()::setName, packet.getApplicant().getName(), valueAfter(lines, "APPLICANT NAME"));
        setIfMissing(packet.getApplicant()::setAddress, packet.getApplicant().getAddress(), valueAfter(lines, "RESIDENTIAL ADDRESS"));
        setIfMissing(packet.getApplicant()::setPhone, packet.getApplicant().getPhone(), valueAfter(lines, "PHONE"));
        setIfMissing(packet.getApplicant()::setEmail, packet.getApplicant().getEmail(), valueAfter(lines, "EMAIL"));
        setIfMissing(packet.getApplicant()::setAgeBand, packet.getApplicant().getAgeBand(), valueAfter(lines, "AGE BAND"));
        setIfMissing(packet.getLoanRequest()::setRequestedAmount, packet.getLoanRequest().getRequestedAmount(), money(valueAfter(lines, "REQUESTED AMOUNT")));
        setIfMissing(packet.getLoanRequest()::setRequestedTermMonths, packet.getLoanRequest().getRequestedTermMonths(), term(valueAfter(lines, "REQUESTED TERM")));
        setIfMissing(packet.getLoanRequest()::setPurposeCode, packet.getLoanRequest().getPurposeCode(), valueAfter(lines, "PURPOSE CODE"));
        setIfMissing(packet.getEmployment()::setEmployer, packet.getEmployment().getEmployer(), valueAfter(lines, "EMPLOYER OR PAYER"));
        setIfMissing(packet.getEmployment()::setJobTitle, packet.getEmployment().getJobTitle(), valueAfter(lines, "POSITION OR ROLE"));
        setIfMissing(packet.getEmployment()::setTenure, packet.getEmployment().getTenure(), valueAfter(lines, "CURRENT TENURE"));
        setIfMissing(packet.getEmployment()::setIncomeSource, packet.getEmployment().getIncomeSource(), valueAfter(lines, "INCOME SOURCE"));
        setIfMissing(packet.getIncome()::setStatedGrossMonthlyIncome, packet.getIncome().getStatedGrossMonthlyIncome(), money(valueAfter(lines, "STATED MONTHLY INCOME")));
        setIfMissing(packet.getLiabilities()::setExistingMonthlyDebt, packet.getLiabilities().getExistingMonthlyDebt(), money(valueAfter(lines, "EXISTING OBLIGATIONS")));
    }

    private void parseIdentitySummary(List<String> lines, ExtractedPacket packet) {
        setIfMissing(packet.getApplicant()::setName, packet.getApplicant().getName(), valueAfter(lines, "APPLICANT"));
        setIfMissing(packet.getApplicant()::setApplicantId, packet.getApplicant().getApplicantId(), valueAfter(lines, "APPLICANT ID"));
        setIfMissing(packet.getIdentity()::setOutcome, packet.getIdentity().getOutcome(), valueAfter(lines, "OUTCOME"));
        setIfMissing(packet.getIdentity()::setGovernmentIdToken, packet.getIdentity().getGovernmentIdToken(), valueAfter(lines, "GOVERNMENT ID TOKEN"));
        setIfMissing(packet.getIdentity()::setAddressToken, packet.getIdentity().getAddressToken(), valueAfter(lines, "ADDRESS TOKEN"));
        setIfMissing(packet.getIdentity()::setPhoneToken, packet.getIdentity().getPhoneToken(), valueAfter(lines, "PHONE TOKEN"));
    }

    private void parsePayStatement(List<String> lines, ExtractedPacket packet) {
        setIfMissing(packet.getEmployment()::setEmployer, packet.getEmployment().getEmployer(), firstBusinessLine(lines));
        setIfMissing(packet.getApplicant()::setName, packet.getApplicant().getName(), valueAfter(lines, "EMPLOYEE"));
        setIfMissing(packet.getEmployment()::setJobTitle, packet.getEmployment().getJobTitle(), firstPresent(lines, "POSITION", "ROLE"));
        setIfMissing(packet.getIncome()::setPayStatementMonthlyGross, packet.getIncome().getPayStatementMonthlyGross(),
                money(firstPresent(lines, "MONTHLYIZED GROSS", "MONTHLYIZED GROSS EARNINGS")));
        setIfMissing(packet.getIncome()::setNetPay, packet.getIncome().getNetPay(), money(firstPresent(lines, "NET PAY", "NET PAYMENT")));
    }

    private void parseAccountActivity(List<String> lines, ExtractedPacket packet) {
        setIfMissing(packet.getApplicant()::setName, packet.getApplicant().getName(), valueAfter(lines, "ACCOUNT HOLDER"));
        setIfMissing(packet.getIncome()::setVerifiedGrossMonthlyIncome, packet.getIncome().getVerifiedGrossMonthlyIncome(), money(valueAfter(lines, "TOTAL CREDITS")));
        setIfMissing(packet.getBanking()::setAccountToken, packet.getBanking().getAccountToken(), valueAfter(lines, "ACCOUNT TOKEN"));
        setIfMissing(packet.getBanking()::setStatementWindow, packet.getBanking().getStatementWindow(), valueAfter(lines, "STATEMENT WINDOW"));
        setIfMissing(packet.getBanking()::setEndingBalance, packet.getBanking().getEndingBalance(), money(valueAfter(lines, "ENDING BALANCE")));
    }

    private void parseLiabilitySchedule(List<String> lines, ExtractedPacket packet) {
        setIfMissing(packet.getApplicant()::setName, packet.getApplicant().getName(), valueAfter(lines, "APPLICANT"));
        setIfMissing(packet.getIncome()::setVerifiedGrossMonthlyIncome, packet.getIncome().getVerifiedGrossMonthlyIncome(), money(valueAfter(lines, "VERIFIED INCOME")));
        setIfMissing(packet.getLiabilities()::setDebtToIncome, packet.getLiabilities().getDebtToIncome(), valueAfter(lines, "POLICY DTI"));
        setIfMissing(packet.getLiabilities()::setProposedMonthlyPayment,
                packet.getLiabilities().getProposedMonthlyPayment(),
                money(valueAfter(lines, "PROPOSED CLOUDBANK PAYMENT")));
    }

    private void parseContractorIncome(List<String> lines, ExtractedPacket packet) {
        setIfMissing(packet.getEmployment()::setEmployer, packet.getEmployment().getEmployer(), firstBusinessLine(lines));
        setIfMissing(packet.getEmployment()::setIncomeSource, packet.getEmployment().getIncomeSource(), "Self-employment");
        setIfMissing(packet.getApplicant()::setName, packet.getApplicant().getName(), valueAfter(lines, "RECIPIENT"));
        setIfMissing(packet.getIncome()::setVerifiedGrossMonthlyIncome, packet.getIncome().getVerifiedGrossMonthlyIncome(), money(valueAfter(lines, "MONTHLY AVERAGE")));
        packet.getValidationSignals().add("recurring_contract_evidence_unavailable");
    }

    private List<String> parseSignals(String documentType, List<String> lines) {
        List<String> signals = new ArrayList<>();
        String text = String.join("\n", lines).toLowerCase(Locale.ROOT);
        if ("income_clarification_request".equals(documentType)) {
            signals.add("income_evidence_requires_clarification");
        }
        if ("relationship_signal_summary".equals(documentType)) {
            signals.add("shared_attribute_signal_requires_review");
        }
        if ("document_receipt".equals(documentType)) {
            signals.add("document_processing_retry_possible");
        }
        if (text.contains("additional review")) {
            signals.add("additional_review_indicated");
        }
        if (text.contains("recurring contract evidence") && text.contains("unavailable")) {
            signals.add("recurring_contract_evidence_unavailable");
        }
        return signals;
    }

    private String valueAfter(List<String> lines, String label) {
        String wanted = label.toUpperCase(Locale.ROOT);
        for (int i = 0; i < lines.size(); i++) {
            if (lines.get(i).toUpperCase(Locale.ROOT).equals(wanted)) {
                for (int j = i + 1; j < Math.min(lines.size(), i + 4); j++) {
                    String candidate = lines.get(j);
                    if (!candidate.isBlank() && !candidate.toUpperCase(Locale.ROOT).equals(wanted)) {
                        return candidate;
                    }
                }
            }
        }
        return null;
    }

    private String firstPresent(List<String> lines, String... labels) {
        for (String label : labels) {
            String value = valueAfter(lines, label);
            if (value != null) {
                return value;
            }
        }
        return null;
    }

    private String firstBusinessLine(List<String> lines) {
        for (String line : lines) {
            String normalized = line.toLowerCase(Locale.ROOT);
            if (!line.equals("CloudBank")
                    && !normalized.contains("document intake packet")
                    && !line.startsWith("APP-")
                    && !line.startsWith("EMP-")
                    && !line.equalsIgnoreCase("PAY")
                    && !line.equalsIgnoreCase("PAYROLL")
                    && !line.equalsIgnoreCase("STATEMENT")
                    && !line.equalsIgnoreCase("CONTRACTOR")
                    && !line.equalsIgnoreCase("ADVICE")
                    && !line.equalsIgnoreCase("PAYROLL ADVICE")
                    && !line.equalsIgnoreCase("Employee Pay Statement")
                    && !line.equalsIgnoreCase("Earnings Statement")
                    && !line.equalsIgnoreCase("Employee Earnings Record")) {
                return line;
            }
        }
        return null;
    }

    private String firstMatch(List<String> lines, Pattern pattern) {
        for (String line : lines) {
            Matcher matcher = pattern.matcher(line);
            if (matcher.find()) {
                return matcher.group(1);
            }
        }
        return null;
    }

    private Double money(String value) {
        if (value == null) {
            return null;
        }
        Matcher matcher = MONEY.matcher(value);
        if (!matcher.find()) {
            return null;
        }
        return Double.parseDouble(matcher.group(1).replace(",", ""));
    }

    private Integer term(String value) {
        if (value == null) {
            return null;
        }
        Matcher matcher = TERM.matcher(value);
        return matcher.find() ? Integer.parseInt(matcher.group(1)) : null;
    }

    private <T> void setIfMissing(java.util.function.Consumer<T> setter, T current, T value) {
        if (current == null && value != null) {
            setter.accept(value);
        }
    }
}
