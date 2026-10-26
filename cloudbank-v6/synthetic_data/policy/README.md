# CloudBank Personal Loan Policy Corpus

This directory contains policy documents for the CloudBank personal loan platform. They are intended for CloudBank internal policy retrieval, workflow evaluation, and grounded explanation generation.

The corpus is designed for:

- deterministic decision-rule evaluation;
- policy retrieval and RAG retrieval;
- grounded Spring AI explanations;
- manual-review workflows;
- traceable policy evidence with stable IDs;
- database security and deep data security controls.

## Corpus Rules

- Applicant names, documents, addresses, employers, and account references must be handled under CloudBank data-classification rules.
- LLMs may retrieve and summarize these policies, but they must not make the final loan decision.
- Deterministic rules produce `APPROVED`, `REJECTED`, or `MANUAL_REVIEW`.
- Ambiguity, missing evidence, contradictory evidence, or protected-class risk must route to manual review.
- Retrieval must enforce role-based access before policy text is supplied to an AI tool, prompt, explanation service, or user interface.
- Sections marked `UNDERWRITER` must not be retrieved, displayed, summarized, cited, or paraphrased for a `LOAN_OFFICER` session.

## Role-Based Access

Policy chunks should carry role-access metadata. The primary retrieval roles are:

- `LOAN_OFFICER`: may retrieve product, documentation, status, explanation, and assigned-application workflow policy needed to support applicants and manual-review intake.
- `UNDERWRITER`: may retrieve all loan-officer policy plus restricted underwriting, fraud-signal, exception, pricing-tier, audit, and security-control policy.

The effective access rule is an allow-list. A chunk is accessible only when the active user role is included in `access_roles`.

## Documents

| File | Policy ID | Purpose |
|----|----|----|
| `policy_corpus_manifest.json` | `POLICY-CORPUS-2026.0` | Machine-readable inventory and retrieval metadata |
| `POLICY-2026.0-MASTER.md` | `POLICY-2026.0` | Governing policy summary and decision hierarchy |
| `CBPL-100-eligibility-and-product-scope.md` | `CBPL-100` | Product eligibility, permitted uses, and baseline applicant requirements |
| `CBPL-110-identity-fraud-and-applicant-integrity.md` | `CBPL-110` | Identity, duplicate application, fraud, and integrity checks |
| `CBPL-120-income-employment-and-documentation.md` | `CBPL-120` | Income, employment, document consistency, and verification standards |
| `CBPL-130-credit-capacity-and-debt-to-income.md` | `CBPL-130` | Capacity, DTI, credit-history, and affordability rules |
| `CBPL-140-pricing-terms-and-risk-tiering.md` | `CBPL-140` | Pricing bands, loan terms, amount limits, and risk tiering |
| `CBPL-150-manual-review-exceptions-and-overrides.md` | `CBPL-150` | Manual review triggers, exception handling, and override controls |
| `CBPL-160-adverse-action-and-explanation-standards.md` | `CBPL-160` | Explanation language, adverse-action style, and decision transparency |
| `CBPL-170-data-security-audit-and-ai-use.md` | `CBPL-170` | Security, audit, redaction, AI boundaries, and retrieval safeguards |

## Suggested Retrieval Metadata

Recommended metadata columns for vector chunks:

- `policy_id`
- `policy_version`
- `section_id`
- `chunk_id`
- `title`
- `policy_domain`
- `decision_relevance`
- `effective_date`
- `data_classification`
- `access_roles`
- `restricted_to`
- `role_filter_required`

Every chunk derived from this corpus should include `data_classification=restricted` unless a lower classification is explicitly assigned.
