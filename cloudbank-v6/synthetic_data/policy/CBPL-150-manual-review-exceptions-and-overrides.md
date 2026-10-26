# CBPL-150: Manual Review, Exceptions, and Overrides

**Policy ID:** `CBPL-150`  
**Version:** 2026.0  
**Effective date:** 2026-01-01  
**Status:** Active policy  
**Policy domain:** Manual review  
**Default access roles:** `LOAN_OFFICER`, `UNDERWRITER`  
**Underwriter-only sections:** `S3`, `S4`, `S5`

## S1. Purpose

Manual review exists to handle applications that cannot be safely or fairly resolved through automatic deterministic rules. Manual review is not a failure state. It is the expected outcome when evidence is incomplete, conflicting, ambiguous, elevated-risk, or requires human judgment in product operations.

The CloudBank personal loan platform reference workflow `APP-MR-002` should document a clean manual-review path.

## S2. Required Manual-Review Triggers

The decision service must return `MANUAL_REVIEW` when any of the following are present and no hard reject rule applies:

- income documents are inconsistent beyond automatic tolerance;
- income evidence is missing or low confidence;
- DTI is above the automatic threshold but not above the hard reject threshold;
- identity evidence requires additional verification;
- graph shared-attribute signal is unresolved;
- spatial risk signal requires contextual review;
- purpose code is unclear;
- pricing calculation is unavailable but retry is not appropriate;
- policy retrieval is ambiguous or insufficient;
- AI tool execution fails after allowed retry.

Manual review must include a reason code and at least one policy citation.

## S3. Combined Risk Signals

Low-severity signals should not automatically reject an application. When two or more low-severity signals occur together, the system should route to manual review.

Examples:

- minor income inconsistency plus shared-employer graph signal;
- address near zone boundary plus DTI above 43 percent;
- recent job change plus document extraction confidence below threshold;
- duplicate device token plus missing income documentation.

The system must avoid treating graph or spatial signals as direct evidence of creditworthiness. They are workflow signals for additional review.

## S4. Exception Authority

Only an underwriter role may approve a documented exception. Exceptions must be limited to the policy boundaries and cannot override:

- confirmed fraud signal;
- ineligible product purpose;
- blocked identity token;
- missing required identity evidence after allowed workflow attempts;
- hard reject DTI rule unless an approved exception policy applies.

Every exception must include:

- reviewer ID;
- exception reason;
- policy section;
- before and after decision state;
- timestamp;
- audit event ID.

## S5. Override Controls

Loan officers may recommend but not finalize exceptions. Admin users may configure application data but may not approve credit decisions.

The workflow must enforce role separation for:

- document request;
- manual-review assignment;
- exception recommendation;
- exception approval;
- final decision update;
- audit inspection.

Deep data security or equivalent database policy should ensure that reviewers see only applications and policy evidence they are authorized to access.

## S6. Operational Failure and Recovery

An operational failure may return `FAILED_RETRYABLE` before recovery. Examples include:

- temporary policy retrieval outage;
- AI explanation service timeout;
- document extraction service unavailable;
- trace correlation write failure;
- workflow task timeout.

The workflow must retry according to configured limits. If retry succeeds, the workflow may continue. If retry fails, the application should route to `MANUAL_REVIEW` with an operational-review reason unless the failure prevents safe continuation.

The reference workflow `APP-OPFAIL-004` should document a retryable failure followed by recovery.

## S7. Manual Review Explanation

Manual-review communication should be neutral and specific:

```text
Your application requires additional review because submitted income evidence needs verification.
```

Avoid speculative, accusatory, or unsupported language:

```text
Your documents appear fraudulent.
```

The AI explanation service may draft a manual-review summary, but the final reason code must come from deterministic workflow state and decision facts.

## S8. Review Timeframes

The platform may display review timeframes. Suggested values:

- standard manual review: 1 to 2 business days;
- document clarification: 2 to 3 business days after document receipt;
- operational recovery review: same day when the service recovers.

These values must not be shown as binding service commitments unless approved for customer-facing communications.

Recommended chunk IDs include `CBPL-150-S2-C01`, `CBPL-150-S3-C01`, `CBPL-150-S4-C01`, and `CBPL-150-S6-C01`.
