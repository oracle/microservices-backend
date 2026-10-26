# CBPL-120: Income, Employment, and Documentation

**Policy ID:** `CBPL-120`  
**Version:** 2026.0  
**Effective date:** 2026-01-01  
**Status:** Active policy  
**Policy domain:** Income verification  
**Default access roles:** `LOAN_OFFICER`, `UNDERWRITER`  
**Underwriter-only sections:** None

## S1. Purpose

This policy defines income, employment, and document-validation standards for CloudBank's personal loan workflow. Income evidence is used to evaluate ability to repay, calculate debt-to-income, support policy explanations, and determine whether an application may be approved automatically or requires manual review.

All income and employment values in product operations must be handled under CloudBank data-classification and verification requirements.

## S2. Required Income Facts

The decision service should receive:

- stated gross monthly income;
- verified gross monthly income;
- income source type;
- employment status;
- employment tenure band;
- document validation status;
- income consistency result;
- income evidence timestamp;
- data classification marker.

Verified income must be based on structured facts extracted from submitted documents or verified data sources. The LLM must not infer income that is not present in structured decision facts.

## S3. Acceptable Income Sources

Acceptable sources for automatic evaluation include:

- salaried employment;
- hourly employment with stable average hours;
- recurring retirement income;
- recurring disability or benefits income where included in policy rules;
- recurring self-employment income with required documentation.

Unstable or unclear income sources should route to `MANUAL_REVIEW`, not automatic rejection, unless another hard reject rule applies.

## S4. Income Documentation Consistency

Income documentation is consistent when stated income, extracted paystub metadata, bank-statement metadata, and employment facts align within the configured tolerance.

The default tolerance is:

- monthly income difference less than or equal to 10 percent for automatic processing;
- monthly income difference greater than 10 percent and less than or equal to 20 percent routes to `MANUAL_REVIEW`;
- monthly income difference greater than 20 percent routes to `MANUAL_REVIEW` and may contribute to rejection if paired with other severe inconsistencies.

The manual-review reference workflow `APP-MR-002` should cite this section when paystub and bank-statement metadata do not fully align.

## S5. Minimum Income Rule

For the unsecured personal loan product, verified gross monthly income should be at least USD 2,500 for automatic approval consideration.

Applications below USD 2,500 may route to:

- `MANUAL_REVIEW` when evidence is incomplete or the requested amount is small and other capacity factors are strong;
- `REJECTED` when verified income is materially insufficient for the requested payment and no mitigating policy applies.

The system must use verified income, not stated income, for final capacity calculations.

## S6. Employment Stability

Employment tenure should be considered in context:

- 12 months or more with current employer supports automatic processing;
- 6 to 11 months may support automatic processing if income is stable and DTI is within policy;
- fewer than 6 months routes to `MANUAL_REVIEW` unless other stable recurring income is present;
- recent job change with higher income requires documentation consistency review.

Employment stability must not be used as a proxy for protected-class characteristics.

## S7. Self-Employment Documentation

Self-employment requires additional evidence in product operations:

- tax-summary metadata;
- bank-statement metadata;
- business-income consistency token;
- income averaging rule.

Self-employment may be approved automatically only when the submitted evidence indicates stable recurring income and the averaged verified income satisfies capacity policy.

## S8. Missing or Low-Confidence Documents

The system must route to `MANUAL_REVIEW` when:

- required income documents are missing;
- extraction confidence is below the configured threshold;
- document type is unsupported;
- document metadata is internally inconsistent;
- document age exceeds the allowed window;
- pay frequency cannot be determined.

The explanation service should describe the missing or inconsistent evidence without exposing raw document text.

## S9. Evidence and Citations

Decision explanations that cite income policy should identify whether the issue was minimum income, documentation consistency, employment stability, or missing evidence.

Recommended chunk IDs include `CBPL-120-S4-C01`, `CBPL-120-S5-C01`, `CBPL-120-S6-C01`, and `CBPL-120-S8-C01`.
