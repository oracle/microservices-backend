# Ready geocoded loan intake

This synthetic packet can open any number of new applications. Its PDFs have no
CloudBank application ID. Intake assigns application/document IDs; upload and
workflow extraction use those IDs from the authorized API context.

| File | Use |
| --- | --- |
| `application.json` | Shared intake template for GUI defaults and CLI smoke tests. No runtime IDs, credentials, workflow mode or local paths. |
| `loan_application.pdf` | Required LOAN_APPLICATION: Synthetic Smoke Applicant, USD 5000, 24 months, Novereign Systems Cooperative, monthly income USD 7200. |
| `pay_statement_novereign_systems.pdf` | Required PAY_STATEMENT for the same applicant/employer, monthly gross USD 7200. |
| `manual-review/loan_application.pdf` | Optional employer-conflict replacement used by `--manual-review`; upload instead of the standard loan PDF. |

The template uses the geocoding demonstration address previously supplied by
`src/workflows/geocoded-loan-address.json`. GUI and CLI append a fresh run ID to
scenario/contact/address correlation tokens. The JSON is a reusable request
template, not a stored application or a workflow input payload.

## GUI

Open New application. The form reads its defaults from `application.json`.
Select the two standard PDFs, create the application, upload both documents,
wait for received status and stored byte counts, then start processing.
No PDF generation or manual copying of the returned application ID is required.

## OKE smoke test

From the repository root, with the configured cluster context and namespace:

```bash
./src/workflows/start-geocoded-loan-oke.sh "$KUBE_CONTEXT" \
  --namespace "$MICROTX_NAMESPACE" \
  --application-file synthetic_data/customer_packets/demo_geocoded_loan/application.json
```

The helper reads the JSON, creates a fresh application, uploads its sibling PDFs,
waits for dispatch and verifies geographic-risk evidence. Credentials stay in
the existing protected environment configuration. It never completes a HUMAN
task and does not guarantee a final lending outcome.

To exercise employer-conflict manual review, use the component's OKE helper:

```bash
./src/loan-application-service/smoke-test-obaas.sh "$KUBE_CONTEXT" \
  --namespace "$MICROTX_NAMESPACE" --from-env --manual-review \
  --application-file synthetic_data/customer_packets/demo_geocoded_loan/application.json
```

The same `--application-file` option is accepted by the host-based
`src/loan-application-service/smoke-test.sh`; choose its usual `WORKFLOW_MODE`.
This smoke adapter supports one LOAN_APPLICATION and one PAY_STATEMENT, with
safe unique PDF basenames relative to the template directory. Additional
document types remain available through the normal intake APIs/GUI.

## Fixture maintenance

`generate_pdfs.py` uses ReportLab to author the checked-in PDFs from the JSON
and fixed synthetic employment/income facts. It is maintainer tooling, never
part of opening an application. It was rendered with ReportLab 5.0.1; for fixture
maintenance, run `uv run --with reportlab==5.0.1 python synthetic_data/customer_packets/demo_geocoded_loan/generate_pdfs.py`
from the repository root. Existing corpus packets remain unchanged.
New extraction does not search PDF text for a runtime application ID, and the
active `document-review-v2` profile does not require or compare such a value.
Redeploy document-ingest and document-review-service before testing this packet.
