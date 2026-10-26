# CBPL-140: Pricing, Terms, and Risk Tiering

**Policy ID:** `CBPL-140`  
**Version:** 2026.0  
**Effective date:** 2026-01-01  
**Status:** Active policy  
**Policy domain:** Pricing and terms  
**Default access roles:** `UNDERWRITER`  
**Loan-officer accessible sections:** `S1`, `S3`, `S5`, `S7`, `S8`  
**Underwriter-only sections:** `S2`, `S4`, `S6`

## S1. Purpose

This policy defines the pricing, loan amount, and term rules used in the CloudBank personal loan program. Pricing values must be presented only through approved offer disclosures and customer communication channels.

The program should use pricing to support affordability calculations, offer generation, and policy explanations.

## S2. Loan Amount Limits

The base product supports requested amounts from USD 1,000 to USD 35,000.

Risk tier may reduce the maximum approvable amount:

- `CB-A`: up to USD 35,000;
- `CB-B`: up to USD 25,000;
- `CB-C`: up to USD 15,000;
- `CB-D`: manual review only;
- `CB-X`: ineligible.

The approved amount must not exceed the applicant's requested amount.

## S3. Term Rules

Available terms are:

- 24 months;
- 36 months;
- 48 months;
- 60 months.

Terms longer than 36 months require verified income, acceptable DTI, and no unresolved manual-review trigger. A 60-month term is not available for elevated-risk applications unless an underwriter approves a documented exception.

## S4. APR Bands

The program may assign APR bands:

- `CB-A`: 8.99 percent to 12.99 percent;
- `CB-B`: 13.00 percent to 18.99 percent;
- `CB-C`: 19.00 percent to 24.99 percent;
- `CB-D`: no automatic offer;
- `CB-X`: no offer.

The UI and generated explanation must display APR values only when they are present in approved offer terms. Customer-facing disclosures must follow approved offer communication standards.

## S5. Payment Calculation

The proposed payment must be calculated deterministically using amount, term, and APR. If payment calculation fails, the application must route to `MANUAL_REVIEW` or `FAILED_RETRYABLE` depending on the failure source.

Payment calculation output should include:

- requested amount;
- evaluated amount;
- term;
- APR;
- monthly payment;
- calculation timestamp;
- policy version.

## S6. Risk Tier Changes

Risk tier may change during workflow when new verified facts arrive. A downgrade from `CB-B` to `CB-C`, or from `CB-C` to `CB-D`, must be audited and may require manual review.

Risk tier must not be changed by the AI explanation service. AI may summarize the reason for a tier change only when the deterministic decision facts identify the cause.

## S7. Pricing Explanation Rules

Explanations should be plain and bounded. Acceptable:

```text
The offer terms reflect the evaluated risk tier, requested amount, verified income, and affordability calculation.
```

Avoid:

```text
The AI selected the best rate for the customer.
```

The system should cite pricing policy only when pricing or terms materially affect approval, manual review, or rejection.

## S8. Offer Expiration

Approved offers expire after 30 days or when the policy version changes, whichever comes first. Expired offers may be re-evaluated using the current policy version and current policy configuration.

Recommended chunk IDs include `CBPL-140-S2-C01`, `CBPL-140-S3-C01`, `CBPL-140-S4-C01`, and `CBPL-140-S5-C01`.
