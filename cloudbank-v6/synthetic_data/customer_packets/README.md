# CloudBank Customer Packet Corpus

This directory contains generated non-production customer document packets for the CloudBank personal loan workflow. The PDFs are intentionally realistic in structure and tone so document extraction, policy retrieval, workflow routing, and explanation services can be exercised with stable inputs.

The PDFs do not visibly mark themselves as generated artifacts. Runtime systems should rely on the manifests and repository context for safe handling, while treating the PDFs as ordinary customer-provided documents during extraction.

## Directory Layout

- `customer_packet_manifest.json`: corpus-level inventory and expected outcomes.
- `app_apr_001_elena_parker/`: fast approval packet.
- `app_mr_002_maya_chen/`: manual review packet for inconsistent income evidence.
- `app_rej_003_daniel_rojas/`: rejection packet for capacity and income support failure.
- `app_opfail_004_priya_natarajan/`: retryable operational failure packet with recovery.
- `app_risk_005_jordan_brooks/`: manual review packet for relationship-signal routing.
- `demo_geocoded_loan/`: [ready intake packet](demo_geocoded_loan/README.md) with
  `application.json` shared by the GUI and CLI, two reusable PDFs without runtime
  application IDs, and an optional employer-conflict loan variant.

## Policy Coverage

Each packet includes customer-facing and CloudBank-generated intake evidence needed by the 2026.0 personal-loan policies:

- loan application with product purpose, requested amount, term, applicant, income, consent, jurisdiction, and data-classification facts;
- applicant disclosure and verification consent record;
- identity verification summary with tokenized identity, address, phone, email, and document metadata facts;
- address and jurisdiction verification;
- income evidence validation with employment status, tenure band, pay frequency, confidence, consistency, and verified-income facts;
- income source evidence, account activity, liability schedule, and payment calculation summary;
- scenario-specific review, recovery, or relationship-signal evidence where the expected outcome requires it.

Packet manifests include policy-alignment facts that explain why each scenario should resolve to `APPROVED`, `MANUAL_REVIEW`, `REJECTED`, or retryable recovery under the policy corpus.

## Deterministic Test Use

Document-ingest tests and its component smoke test use PDFs directly from this
corpus; they do not depend on packet manifests or generator internals. The
current smoke test selects three files from
`app_apr_001_elena_parker/`: `loan_application.pdf`,
`pay_statement_novereign_systems.pdf`, and `liability_schedule.pdf`. It sends
them to the authenticated diagnostic extraction endpoint, verifies stable
document classification and replay behavior, and displays a short structured
JSON excerpt.

That smoke test intentionally does not consume application or BLOB state left
by the loan-service smoke test. Complete upload, workflow invocation, authorized
BLOB retrieval, extraction persistence, and status callbacks require a future
repository-level system smoke test that creates and cleans up its own state.

## Data Safety

- Contact values use reserved patterns such as `555-01xx` phone numbers and `example.invalid` email addresses.
- Street names, localities, employers, identifiers, account tokens, and document references are invented.
- Documents avoid raw government identifiers, full account numbers, production credentials, and credit bureau artifacts.
- Do not ingest this README as customer-provided document content.
