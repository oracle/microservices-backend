# CloudBank Personal Loan Policy Manual 2026.0

**Policy ID:** `POLICY-2026.0`  
**Effective date:** 2026-01-01  
**Owner:** CloudBank Consumer Credit Policy Office  
**Status:** Active policy  
**Applies to:** Unsecured retail personal loan applications in the CloudBank personal loan platform  
**Default access roles:** `LOAN_OFFICER`, `UNDERWRITER`  
**Underwriter-only sections:** `S6`

## S1. Purpose

This manual defines the CloudBank approval procedures for unsecured retail personal loans used in the CloudBank personal loan platform policy program. It describes eligibility, identity integrity, income verification, affordability, pricing, manual review, explanation standards, auditability, and AI-use boundaries.

The policy is written to support the CloudBank loan origination workflow.

## S2. Decision Hierarchy

CloudBank uses a deterministic decision service as the source of the credit recommendation. The decision service may return:

- `APPROVED`
- `REJECTED`
- `MANUAL_REVIEW`

The decision service must use structured application facts, verified evidence, and policy rules. An LLM, chatbot, agent, or explanation service must not set the final decision result.

If policy evidence is incomplete, contradictory, stale, unavailable, or ambiguous, the application must be routed to `MANUAL_REVIEW` unless a hard reject rule applies.

## S3. Policy Domains

The 2026.0 policy corpus is organized into these domains:

- eligibility and product scope;
- identity, fraud, and applicant integrity;
- income, employment, and documentation;
- credit capacity and debt-to-income;
- pricing, terms, and risk tiering;
- manual review, exceptions, and overrides;
- adverse action and explanation standards;
- data security, audit, and AI use.

Each domain has its own policy file with stable section identifiers. Retrieval systems should cite the policy ID, section ID, and chunk ID used to generate an explanation.

## S4. Role Responsibilities

The applicant may submit an application, provide documents, and view status or final communication for their own application.

The loan officer may review applications assigned to a queue, request clarifying documentation, and recommend manual-review outcomes. The loan officer may not override hard reject rules.

The underwriter may approve documented exceptions within defined limits and must record an exception reason.

The admin may manage configuration, users, and authorized operational data in controlled environments. Admin access must not be used to bypass underwriting policy.

The auditor may view decision facts, policy citations, audit records, and redacted trace evidence. The auditor should not receive unnecessary applicant-sensitive values.

## S5. AI Boundary

AI may support document extraction, policy retrieval, question answering, explanation drafting, status summarization, and workflow assistance. AI may not make the credit decision.

AI-generated explanations must be grounded in structured decision facts and retrieved policy evidence. AI output must include the decision source when shown in product operations:

```text
decisionSource=DETERMINISTIC_POLICY_RULES
```

AI must not create new eligibility criteria, infer protected-class characteristics, recommend exceptions outside policy, or expose data outside the active user's authorization.

## S6. Audit and Evidence Standard

Every decision must be explainable from stored evidence. At minimum, the system should retain:

- application ID;
- reference workflow ID;
- workflow ID;
- decision ID;
- policy version;
- retrieved policy evidence IDs;
- decision result;
- manual-review reason when applicable;
- data classification marker;
- trace ID or telemetry correlation ID.

Evidence must be sufficient for a reviewer to reconstruct why the system produced `APPROVED`, `REJECTED`, or `MANUAL_REVIEW`.

## S7. Effective Versioning

This policy version is `2026.0`. Controlled environments may load future policy versions, but CloudBank personal loan platform reference workflows must use `policy_version=2026.0` unless explicitly testing version migration.

Policy updates must preserve stable references for reference workflows or include a migration map from old chunk IDs to new chunk IDs.
