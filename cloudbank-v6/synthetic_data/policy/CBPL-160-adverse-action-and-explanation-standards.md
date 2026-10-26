# CBPL-160: Adverse Action and Explanation Standards

**Policy ID:** `CBPL-160`  
**Version:** 2026.0  
**Effective date:** 2026-01-01  
**Status:** Active policy  
**Policy domain:** Explanations and notices  
**Default access roles:** `LOAN_OFFICER`, `UNDERWRITER`  
**Underwriter-only sections:** None

## S1. Purpose

This policy defines explanation standards for the CloudBank personal loan platform. The goal is to produce clear, grounded, reviewable explanations for approved, rejected, and manual-review outcomes while avoiding unsupported claims, protected-class references, and overstatement of AI authority.

This policy is a policy standard for customer-facing explanation content.

## S2. Explanation Inputs

Every generated explanation must be based on:

- deterministic decision result;
- reason codes;
- structured decision facts;
- retrieved policy evidence;
- policy version;
- application ID;
- data classification marker.

The explanation service must not use hidden reasoning, invented facts, raw prompts, raw documents, or unauthorized data to explain a decision.

## S3. Manual Review Explanations

Manual-review explanations should identify the category of unresolved evidence:

- income verification;
- document consistency;
- identity verification;
- DTI or affordability review;
- product purpose clarification;
- operational recovery;
- combined risk signal review.

Manual review should not be described as approval or denial. It is a pending workflow state.

Example:

```text
The application was routed to manual review because income documentation requires verification under CloudBank policy CBPL-120 and manual-review policy CBPL-150.
```

## S4. Rejection Explanations

Rejection explanations must be concise, factual, and tied to reason codes. Examples include:

- requested loan purpose is outside product scope;
- verified income is unavailable after required attempts;
- DTI exceeds the hard reject threshold;
- confirmed fraud signal is present;
- requested amount exceeds product maximum and no eligible lower amount is available.

The explanation must not include unnecessary sensitive details or raw document contents.

## S5. Approval Explanations

Approval explanations may summarize that the application met product eligibility, income verification, capacity, and identity requirements. They may include approved amount, term, and APR where applicable.

The explanation must state offer terms only when those terms are present in approved decision facts.

## S6. Prohibited Explanation Language

The explanation service must avoid:

- "The AI approved your loan."
- "The AI rejected your loan."
- "Fraud was detected" unless a confirmed fraud rule applies.
- "You are risky" or similar broad labels.
- references to protected-class attributes;
- explanations based on graph or spatial signals alone;
- unsupported certainty about document authenticity;
- disclosure of internal security controls beyond safe audit summaries.

## S7. Policy Citation Requirements

Each explanation should include at least one policy citation when policy evidence materially affected the decision. A citation should include:

- policy ID;
- section ID;
- chunk ID where available;
- short title;
- reason category.

Example:

```json
{
  "policyId": "CBPL-120",
  "sectionId": "S4",
  "chunkId": "CBPL-120-S4-C01",
  "reason": "Income documentation consistency"
}
```

## S8. Human Review of Generated Text

Generated text for manual review and rejection should be reviewable by a loan officer or underwriter in product operations. The system may display a suggested explanation, but the recorded reason codes and decision result remain deterministic.

Recommended chunk IDs include `CBPL-160-S3-C01`, `CBPL-160-S4-C01`, `CBPL-160-S6-C01`, and `CBPL-160-S7-C01`.
