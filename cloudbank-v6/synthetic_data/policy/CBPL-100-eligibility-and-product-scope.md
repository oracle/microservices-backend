# CBPL-100: Eligibility and Product Scope

**Policy ID:** `CBPL-100`  
**Version:** 2026.0  
**Effective date:** 2026-01-01  
**Status:** Active policy  
**Policy domain:** Eligibility  
**Default access roles:** `LOAN_OFFICER`, `UNDERWRITER`  
**Underwriter-only sections:** None

## S1. Product Definition

CloudBank's personal loan product is an unsecured installment loan for individual applicants. The product is intended for general consumer purposes such as debt consolidation, household expenses, medical expenses, education-related expenses not otherwise restricted by policy, or approved major purchases.

The product is not a mortgage, auto-secured loan, student loan, business loan, payday loan, credit card, overdraft product, or line of credit.

The program product supports loan amounts from USD 1,000 to USD 35,000 and terms from 24 to 60 months. Product limits may be narrowed by risk tier, affordability, state availability, or manual-review outcome.

## S2. Applicant Eligibility

An applicant is eligible for initial evaluation when all of the following are true:

- the applicant is at least 18 years old;
- the applicant provides a valid identity record;
- the applicant provides a residential address in an eligible jurisdiction;
- the applicant provides income information sufficient for verification;
- the application is submitted for a permitted consumer purpose;
- the applicant agrees to required application disclosures;
- the application is marked with the required data classification.

All identity and address evidence must comply with CloudBank data-classification, privacy, and verification requirements.

## S3. Baseline Approval Preconditions

An application may be approved only when baseline product eligibility, identity integrity, income verification, capacity, policy retrieval, and security checks all pass.

The deterministic decision service must confirm:

- application purpose is permitted;
- requested amount is within product limits;
- minimum verified gross monthly income is met;
- debt-to-income is within the applicable threshold;
- no hard reject identity or integrity condition exists;
- no required document is missing;
- no unresolved high-severity risk signal exists;
- the loan term and payment are affordable under policy.

When these conditions are met and no manual-review trigger is present, the decision service may return `APPROVED`.

## S4. Permitted Uses

The following purpose codes are permitted in product operations:

- `DEBT_CONSOLIDATION`
- `HOME_IMPROVEMENT`
- `MAJOR_PURCHASE`
- `MEDICAL_EXPENSE`
- `HOUSEHOLD_EXPENSE`
- `MOVING_EXPENSE`
- `OTHER_CONSUMER_PURPOSE`

The purpose code should be stored with the application and included in decision facts. The explanation service may summarize the purpose but must not embellish the applicant's reason beyond the submitted value.

## S5. Restricted Uses

The following uses must result in rejection or manual review, depending on the submitted evidence:

- business financing;
- investment or speculative trading;
- illegal activity;
- gambling;
- purchase of restricted goods;
- education financing that should be handled under a different product;
- any purpose inconsistent with unsecured consumer lending.

If the purpose is missing, unclear, or contradicted by document evidence, the application must route to `MANUAL_REVIEW`.

## S6. State and Jurisdiction Rules

The program may include jurisdiction codes to support spatial and policy-routing controls. If an applicant's address falls outside an enabled jurisdiction, the application must not be approved automatically.

Applications in disabled jurisdictions should return `MANUAL_REVIEW` when the issue may be a policy configuration issue and `REJECTED` when the submitted jurisdiction is explicitly outside product scope.

## S7. Duplicate Application Handling

If the same applicant submits more than one active application within a 30-day window, the later application must route to `MANUAL_REVIEW` unless the earlier application is withdrawn or expired.

Duplicate detection must not be based on applicant name alone. It should use applicant ID, document token, address token, phone token, email token, or device token, subject to data-security policy.

## S8. Product Scope Evidence

For a decision explanation, the system may cite this policy when:

- the application was approved because the request was within product scope;
- the application was rejected because the requested use was restricted;
- the application entered manual review because product purpose or jurisdiction was unclear.

Recommended chunk IDs include `CBPL-100-S3-C01`, `CBPL-100-S4-C01`, and `CBPL-100-S5-C01`.
