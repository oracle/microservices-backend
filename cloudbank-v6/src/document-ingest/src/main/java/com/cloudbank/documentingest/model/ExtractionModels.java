// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.documentingest.model;

import java.util.ArrayList;
import java.util.List;

public final class ExtractionModels {

    private ExtractionModels() {
    }

    public record SourceDocument(String name, byte[] content) {
    }

    public record ExtractionResponse(String service, String provider, int packetCount, List<ExtractedPacket> packets) {
    }

    public record DocumentSummary(String fileName, String documentType, int textLineCount) {
    }

    public static final class ExtractedPacket {
        private String packetId;
        // Legacy diagnostic field, deliberately left null. Runtime association
        // uses the authenticated workflow request and persisted application/document keys.
        private String applicationId;
        private Applicant applicant = new Applicant();
        private Employment employment = new Employment();
        private Income income = new Income();
        private LoanRequest loanRequest = new LoanRequest();
        private Liabilities liabilities = new Liabilities();
        private Identity identity = new Identity();
        private Banking banking = new Banking();
        private List<DocumentSummary> documents = new ArrayList<>();
        private List<String> validationSignals = new ArrayList<>();
        private List<String> warnings = new ArrayList<>();

        public ExtractedPacket(String packetId) {
            this.packetId = packetId;
        }

        public String getPacketId() {
            return packetId;
        }

        public String getApplicationId() {
            return applicationId;
        }

        public void setApplicationId(String applicationId) {
            this.applicationId = applicationId;
        }

        public Applicant getApplicant() {
            return applicant;
        }

        public Employment getEmployment() {
            return employment;
        }

        public Income getIncome() {
            return income;
        }

        public LoanRequest getLoanRequest() {
            return loanRequest;
        }

        public Liabilities getLiabilities() {
            return liabilities;
        }

        public Identity getIdentity() {
            return identity;
        }

        public Banking getBanking() {
            return banking;
        }

        public List<DocumentSummary> getDocuments() {
            return documents;
        }

        public List<String> getValidationSignals() {
            return validationSignals;
        }

        public List<String> getWarnings() {
            return warnings;
        }
    }

    public static final class Applicant {
        private String applicantId;
        private String name;
        private String address;
        private String phone;
        private String email;
        private String ageBand;

        public String getApplicantId() {
            return applicantId;
        }

        public void setApplicantId(String applicantId) {
            this.applicantId = applicantId;
        }

        public String getName() {
            return name;
        }

        public void setName(String name) {
            this.name = name;
        }

        public String getAddress() {
            return address;
        }

        public void setAddress(String address) {
            this.address = address;
        }

        public String getPhone() {
            return phone;
        }

        public void setPhone(String phone) {
            this.phone = phone;
        }

        public String getEmail() {
            return email;
        }

        public void setEmail(String email) {
            this.email = email;
        }

        public String getAgeBand() {
            return ageBand;
        }

        public void setAgeBand(String ageBand) {
            this.ageBand = ageBand;
        }
    }

    public static final class Employment {
        private String employer;
        private String jobTitle;
        private String tenure;
        private String incomeSource;

        public String getEmployer() {
            return employer;
        }

        public void setEmployer(String employer) {
            this.employer = employer;
        }

        public String getJobTitle() {
            return jobTitle;
        }

        public void setJobTitle(String jobTitle) {
            this.jobTitle = jobTitle;
        }

        public String getTenure() {
            return tenure;
        }

        public void setTenure(String tenure) {
            this.tenure = tenure;
        }

        public String getIncomeSource() {
            return incomeSource;
        }

        public void setIncomeSource(String incomeSource) {
            this.incomeSource = incomeSource;
        }
    }

    public static final class Income {
        private Double statedGrossMonthlyIncome;
        private Double verifiedGrossMonthlyIncome;
        private Double payStatementMonthlyGross;
        private Double netPay;

        public Double getStatedGrossMonthlyIncome() {
            return statedGrossMonthlyIncome;
        }

        public void setStatedGrossMonthlyIncome(Double statedGrossMonthlyIncome) {
            this.statedGrossMonthlyIncome = statedGrossMonthlyIncome;
        }

        public Double getVerifiedGrossMonthlyIncome() {
            return verifiedGrossMonthlyIncome;
        }

        public void setVerifiedGrossMonthlyIncome(Double verifiedGrossMonthlyIncome) {
            this.verifiedGrossMonthlyIncome = verifiedGrossMonthlyIncome;
        }

        public Double getPayStatementMonthlyGross() {
            return payStatementMonthlyGross;
        }

        public void setPayStatementMonthlyGross(Double payStatementMonthlyGross) {
            this.payStatementMonthlyGross = payStatementMonthlyGross;
        }

        public Double getNetPay() {
            return netPay;
        }

        public void setNetPay(Double netPay) {
            this.netPay = netPay;
        }
    }

    public static final class LoanRequest {
        private Double requestedAmount;
        private Integer requestedTermMonths;
        private String purposeCode;

        public Double getRequestedAmount() {
            return requestedAmount;
        }

        public void setRequestedAmount(Double requestedAmount) {
            this.requestedAmount = requestedAmount;
        }

        public Integer getRequestedTermMonths() {
            return requestedTermMonths;
        }

        public void setRequestedTermMonths(Integer requestedTermMonths) {
            this.requestedTermMonths = requestedTermMonths;
        }

        public String getPurposeCode() {
            return purposeCode;
        }

        public void setPurposeCode(String purposeCode) {
            this.purposeCode = purposeCode;
        }
    }

    public static final class Liabilities {
        private Double existingMonthlyDebt;
        private Double proposedMonthlyPayment;
        private String debtToIncome;

        public Double getExistingMonthlyDebt() {
            return existingMonthlyDebt;
        }

        public void setExistingMonthlyDebt(Double existingMonthlyDebt) {
            this.existingMonthlyDebt = existingMonthlyDebt;
        }

        public Double getProposedMonthlyPayment() {
            return proposedMonthlyPayment;
        }

        public void setProposedMonthlyPayment(Double proposedMonthlyPayment) {
            this.proposedMonthlyPayment = proposedMonthlyPayment;
        }

        public String getDebtToIncome() {
            return debtToIncome;
        }

        public void setDebtToIncome(String debtToIncome) {
            this.debtToIncome = debtToIncome;
        }
    }

    public static final class Identity {
        private String outcome;
        private String governmentIdToken;
        private String addressToken;
        private String phoneToken;

        public String getOutcome() {
            return outcome;
        }

        public void setOutcome(String outcome) {
            this.outcome = outcome;
        }

        public String getGovernmentIdToken() {
            return governmentIdToken;
        }

        public void setGovernmentIdToken(String governmentIdToken) {
            this.governmentIdToken = governmentIdToken;
        }

        public String getAddressToken() {
            return addressToken;
        }

        public void setAddressToken(String addressToken) {
            this.addressToken = addressToken;
        }

        public String getPhoneToken() {
            return phoneToken;
        }

        public void setPhoneToken(String phoneToken) {
            this.phoneToken = phoneToken;
        }
    }

    public static final class Banking {
        private String accountToken;
        private String statementWindow;
        private Double endingBalance;

        public String getAccountToken() {
            return accountToken;
        }

        public void setAccountToken(String accountToken) {
            this.accountToken = accountToken;
        }

        public String getStatementWindow() {
            return statementWindow;
        }

        public void setStatementWindow(String statementWindow) {
            this.statementWindow = statementWindow;
        }

        public Double getEndingBalance() {
            return endingBalance;
        }

        public void setEndingBalance(Double endingBalance) {
            this.endingBalance = endingBalance;
        }
    }
}
