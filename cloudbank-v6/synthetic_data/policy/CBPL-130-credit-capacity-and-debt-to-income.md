# CBPL-130: Credit Capacity and Debt-to-Income

**Policy ID:** `CBPL-130`  
**Version:** 2026.0  
**Effective date:** 2026-01-01  
**Status:** Active policy  
**Policy domain:** Capacity and affordability  
**Default access roles:** `LOAN_OFFICER`, `UNDERWRITER`  
**Underwriter-only sections:** `S6`, `S7`

## S1. Purpose

This policy defines the capacity, affordability, and debt-to-income rules for CloudBank personal loan decisions. It establishes deterministic underwriting logic and explainable policy retrieval requirements for the CloudBank personal loan platform.

Credit information must be represented through approved decision facts and internal policy categories.

## S2. Capacity Inputs

The capacity calculation should use:

- verified gross monthly income;
- existing monthly debt obligations;
- proposed monthly payment;
- requested amount;
- term;
- credit risk band;
- recent delinquency indicator, if any;
- bankruptcy or charge-off indicator, if any;
- policy version.

The proposed monthly payment must be calculated by deterministic service logic, not by an LLM.

## S3. Debt-to-Income Thresholds

Debt-to-income, or DTI, is calculated as:

```text
(existing monthly debt + proposed monthly payment) / verified gross monthly income
```

The default thresholds are:

- DTI less than or equal to 36 percent: eligible for automatic approval if other requirements pass;
- DTI greater than 36 percent and less than or equal to 43 percent: eligible for automatic approval only for lower-risk tiers and consistent income evidence;
- DTI greater than 43 percent and less than or equal to 50 percent: route to `MANUAL_REVIEW`;
- DTI greater than 50 percent: reject unless an approved exception policy applies.

Manual review is required when DTI calculation uses incomplete or conflicting income evidence.

## S4. Hard Reject Capacity Rules

The decision service should return `REJECTED` when any of the following hard reject rules apply:

- verified income is unavailable and required documents are missing after allowed workflow attempts;
- DTI exceeds 50 percent without an approved exception;
- requested amount exceeds product maximum;
- proposed payment cannot be calculated;
- recent severe delinquency indicator is present;
- open bankruptcy indicator is present;
- confirmed fraud signal is present under identity policy.

The explanation service may cite the relevant capacity rule but must avoid unnecessary sensitive detail.

## S5. Automatic Approval Capacity Rules

An application may be automatically approved when:

- verified income meets the minimum income rule;
- DTI is less than or equal to the applicable threshold;
- credit risk band is acceptable;
- requested amount and term fit product limits;
- no unresolved identity, document, graph, spatial, or security-review trigger is present;
- policy retrieval returns the required supporting rules.

Automatic approval must store the policy version and decision facts used by the deterministic service.

## S6. Credit Risk Bands

The program uses internal credit risk bands:

- `CB-A`: low risk;
- `CB-B`: moderate risk;
- `CB-C`: elevated risk;
- `CB-D`: high risk;
- `CB-X`: reject or blocked status.

The program may map these bands to pricing and review rules. Credit risk bands are internal policy categories and must be explained only through approved reason codes.

## S7. Recent Delinquency Indicators

A recent delinquency indicator may affect the decision:

- `NONE`: no effect;
- `MINOR_RESOLVED`: may proceed if DTI and income pass;
- `RECENT_MINOR`: route to `MANUAL_REVIEW`;
- `RECENT_SEVERE`: reject;
- `UNKNOWN`: route to `MANUAL_REVIEW`.

The explanation should state the policy category, not raw account detail.

## S8. Capacity Explanation Standard

Capacity explanations should identify the main reason and cite policy evidence. Example:

```text
The application was routed to manual review because the proposed payment places total monthly obligations above the automatic approval threshold.
```

The AI explanation service must not invent credit factors that are not present in decision facts.

Recommended chunk IDs include `CBPL-130-S3-C01`, `CBPL-130-S4-C01`, `CBPL-130-S5-C01`, and `CBPL-130-S8-C01`.
