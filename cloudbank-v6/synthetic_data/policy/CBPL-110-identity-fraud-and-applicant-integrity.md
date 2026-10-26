# CBPL-110: Identity, Fraud, and Applicant Integrity

**Policy ID:** `CBPL-110`  
**Version:** 2026.0  
**Effective date:** 2026-01-01  
**Status:** Active policy  
**Policy domain:** Identity and fraud controls  
**Default access roles:** `UNDERWRITER`  
**Loan-officer accessible sections:** `S1`, `S2`, `S3`, `S7`  
**Underwriter-only sections:** `S4`, `S5`, `S6`, `S8`

## S1. Purpose

This policy defines the identity and applicant-integrity checks used for the CloudBank personal loan program. These controls support risk-aware workflow behavior, identity consistency review, and fraud-signal handling.

Identity checks must be deterministic in product operations so expected outcomes remain stable.

## S2. Required Identity Evidence

A complete identity packet should contain:

- `applicant_id`;
- full-name token;
- date-of-birth token or age band;
- address ID;
- phone token;
- email token;
- government-ID token;
- document metadata for identity evidence;
- data classification marker.

The system must tokenize or redact government identifiers, document images, credit bureau records, phone numbers, and email addresses according to CloudBank data-security policy.

## S3. Identity Verification Outcomes

The identity service may return:

- `IDENTITY_VERIFIED`
- `IDENTITY_NEEDS_REVIEW`
- `IDENTITY_REJECT`

`IDENTITY_VERIFIED` means the identity evidence is complete and internally consistent.

`IDENTITY_NEEDS_REVIEW` means evidence is incomplete, inconsistent, stale, or ambiguous but not a hard reject.

`IDENTITY_REJECT` means a hard reject condition exists, such as a blocked identity token, confirmed fraud token, or impossible identity combination.

## S4. Relationship and Shared-Attribute Signals

The graph risk check may identify shared attributes across applications, such as shared address token, employer token, device token, phone token, or bank-account token.

Shared attributes are signals, not automatic denial reasons. A low-severity shared-attribute signal may contribute to `MANUAL_REVIEW` when combined with income inconsistency, address boundary risk, or duplicate application behavior.

A high-severity fraud-ring signal may result in `IDENTITY_REJECT` only when the decision facts explicitly mark the applicant token as blocked or confirmed fraud.

The explanation service must not say that graph analysis "detected fraud" unless the deterministic decision facts include a confirmed fraud rule.

## S5. Duplicate and Velocity Controls

The system should route an application to `MANUAL_REVIEW` when:

- more than one active application is linked to the same applicant ID;
- multiple applications share the same document token within 30 days;
- multiple applicants share the same device token and address token within 14 days;
- the application is resubmitted repeatedly after document-validation failures.

The system may reject when a blocked identity token or confirmed fraud signal is present.

## S6. Document Integrity

Identity documents must have internally consistent metadata. The program should check:

- document type;
- issue-date token;
- expiration-date token;
- applicant-token match;
- address-token match where applicable;
- extraction confidence;
- tamper-signal indicator.

Low confidence or mismatch should route to `MANUAL_REVIEW`. A tamper-signal indicator marked `CONFIRMED_TAMPER` should route to `REJECTED`.

## S7. AI and Fraud Language

AI-generated text must use careful language. Acceptable language:

```text
The application was routed for manual review because identity evidence requires additional verification.
```

Avoid:

```text
The applicant committed fraud.
```

The program should distinguish risk signals from final factual conclusions.

## S8. Audit Requirements

The system must audit identity checks, graph signals, duplicate checks, and manual-review routing. Audit records should include:

- application ID;
- applicant token;
- identity outcome;
- graph signal IDs;
- duplicate-check result;
- decision result;
- policy ID and section;
- timestamp;
- actor or service name.

Recommended chunk IDs include `CBPL-110-S3-C01`, `CBPL-110-S4-C01`, and `CBPL-110-S7-C01`.
