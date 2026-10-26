# CBPL-170: Data Security, Audit, and AI Use

**Policy ID:** `CBPL-170`  
**Version:** 2026.0  
**Effective date:** 2026-01-01  
**Status:** Active policy  
**Policy domain:** Security and AI governance  
**Default access roles:** `UNDERWRITER`  
**Loan-officer accessible sections:** `S1`, `S2`, `S9`  
**Underwriter-only sections:** `S3`, `S4`, `S5`, `S6`, `S7`, `S8`

## S1. Purpose

This policy defines security and AI-use rules for the CloudBank personal loan platform. It aligns policy retrieval, AI explanation, database access, audit, tracing, and customer data safety.

The program must implement strong security practices and maintain auditable evidence of security controls.

## S2. Customer Data Requirement

Applicant data must be handled according to CloudBank privacy, retention, and data-classification requirements. The system must protect:

- names;
- addresses;
- phone numbers;
- email addresses;
- account numbers;
- government identifiers;
- credit reports;
- production credentials;
- restricted bank policy.

Sensitive values must be redacted or tokenized before appearing in screenshots, logs, traces, analytics, prompts, or model responses.

## S3. Least-Privilege Access

The application should separate:

- schema owner;
- migration or admin identity;
- runtime service identity;
- read-only auditor identity;
- ORDS identity where used;
- security-policy owner where used.

Runtime service accounts must not receive broad administrative privileges. Object grants, views, database roles, deep data security, VPD, redaction, or application contexts should enforce the minimum access required.

## S4. Database-Enforced Retrieval Authorization

AI retrieval must not rely only on prompt instructions or application-side filtering. Where supported, the database should enforce row, column, document, and vector retrieval authorization before data reaches:

- Spring AI tools;
- prompt templates;
- LLM calls;
- trace attributes;
- generated explanations;
- application logs.

The program should prove that the same query or vector retrieval pattern can return different authorized results for different end-user roles.

## S5. Logging, Tracing, and Prompt Redaction

The system must not write sensitive values to logs, prompts, traces, metrics, or model responses. Redaction should apply to:

- full names;
- address text;
- raw document text;
- tokens and credentials;
- OTPs and passwords;
- private keys and wallet material;
- full prompts;
- unredacted model responses.

Allowed telemetry attributes include stable identifiers and labels such as:

- `cloudbank.application_id`;
- `cloudbank.workflow_id`;
- `cloudbank.reference_workflow_id`;
- `cloudbank.policy_version`;
- `cloudbank.decision_result`;
- `cloudbank.data_classification=restricted`.

## S6. AI Tool Boundary

AI tools must be narrow, auditable, and role-aware. Approved tool categories include:

- retrieve application facts for the active authorized application;
- retrieve policy evidence for the active authorized role;
- summarize decision facts;
- draft explanation text;
- record explanation output;
- request manual-review assistance.

AI tools must not:

- change decision result;
- approve exceptions;
- bypass database security policy;
- retrieve all applications;
- fetch raw documents unless explicitly authorized;
- expose data for another applicant;
- alter audit records.

## S7. Audit Requirements

Audit records should be created for:

- authentication-sensitive events where available;
- user-management actions;
- application submission;
- document access;
- policy retrieval;
- vector retrieval;
- graph and spatial signal evaluation;
- decision generation;
- manual-review action;
- exception approval;
- AI explanation generation;
- security-policy failures.

Audit records should include stable identifiers and avoid raw sensitive values.

## S8. Security Scanning and Review

Security scanning is required for product operations code and deployment assets. The selected scanner set should include dependency vulnerability scanning, SAST, secrets scanning, container scanning, Helm/Kubernetes scanning, SBOM generation, and API security testing where practical.

AI-assisted review may be used to supplement deterministic scanners for prompt leakage, unsafe tool boundaries, missing authorization checks, and overbroad data retrieval. AI-assisted review does not replace scanner results, tests, or human review.

Critical or high-severity findings, leaked secrets, unauthenticated sensitive endpoints, overly broad database privileges, and telemetry leaks must block release unless explicitly accepted with written rationale.

## S9. Explanation and Retrieval Safety

Generated explanations must cite policy evidence and must not disclose unauthorized facts. If policy retrieval returns no authorized evidence, the explanation service must not use a broader retrieval path. It should route to manual review or return a safe message indicating that additional review is required.

Recommended chunk IDs include `CBPL-170-S3-C01`, `CBPL-170-S4-C01`, `CBPL-170-S5-C01`, `CBPL-170-S6-C01`, and `CBPL-170-S8-C01`.
