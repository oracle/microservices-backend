# CloudBank local Web GUI

The React/TypeScript/Vite GUI uses the running `gateway-bff-service` by default.
It authenticates through the BFF, creates applications, uploads PDFs, explicitly
starts processing, lists pending HUMAN tasks, submits manual reviews, and shows the authorized application list
from `loan-application-service`. The browser receives an HttpOnly session
cookie; it does not read or persist OAuth tokens, client secrets, or passwords.

## Run with the OKE BFF

Node.js 20.19+ or 22.12+ is recommended for Vite 7. Deploy the BFF first with
the [OKE runbook](../../deploy/obaas/gateway-bff-runbook.md). From the repository
root, keep these processes running in separate terminals:

```bash
kubectl --kubeconfig "$(sed -n 's/^CLOUDBANK_KUBECONFIG_PATH=//p' .env)" -n "$(sed -n 's/^MICROTX_NAMESPACE=//p' .env)" port-forward svc/azn-server 8080:8080
kubectl --kubeconfig "$(sed -n 's/^CLOUDBANK_KUBECONFIG_PATH=//p' .env)" -n "$(sed -n 's/^MICROTX_NAMESPACE=//p' .env)" port-forward svc/gateway-bff-service 8089:8089
cd src/cloudbank_ui && npm ci && npm run dev
```

Open `http://127.0.0.1:5173`, select **Sign in with CloudBank**, authenticate
as `obaas-admin`, and open **Applications**. Vite forwards `/bff` and
`/oauth2/authorization` to the local BFF port-forward. The browser must also
reach `azn-server` on port 8080 for the authorization page. **Refresh** and
the status selector load new pages from the BFF. **Sign out** ends the BFF
session. An unavailable BFF produces an explicit connection error; it never
silently substitutes synthetic applications.

Select **New application**, enter synthetic details, and select document files.
The form starts with the standard smoke-test applicant and loan values
(`5000.00`, `24` months, `OTHER_CONSUMER_PURPOSE`, policy `2026.0`) and the
address imported from the shared [`application.json`](../../synthetic_data/customer_packets/demo_geocoded_loan/application.json),
also used by the CLI smoke tests. Scenario and synthetic
phone/email/address tokens receive a fresh run identifier on each new form.
All values remain editable. Two required metadata rows are prefilled:
`LOAN_APPLICATION` and `PAY_STATEMENT`. File pickers remain empty until the
presenter chooses local PDFs; preset filenames are metadata only.

**Create application** first saves JSON metadata with status `SUBMITTED`,
documents `EXPECTED`, and workflow dispatch `DEFERRED`. The same page then shows
the returned application and document IDs. Select **Upload** on each row to send
the actual PDF bytes to the loan service. Successful uploads show `received`
and the stored byte count. Each row has its own retry; successful rows survive
another row's failure. Ambiguous metadata/file matches require selecting the
file again against its explicit returned document ID.

After uploading, select **Start processing**. It explicitly releases the loan
outbox; `202` means scheduling was accepted, not that the workflow completed or
the loan was approved. Return to the list and refresh to see the assigned
workflow ID. Backend checks remain active and there is no client-side input,
file-type, size, or completeness validation. Buttons only guard in-flight or
completed operations. Same-operation upload retries retain their key/file.

This increment covers newly created applications only. Complete creation,
upload, and start on this page; reopening earlier applications and resuming an
unfinished intake after a browser reload remain outside this increment. Files
are transient browser objects, while accepted metadata and uploads are durable.

## PDFs for the geocoded smoke-test path

Both ready PDFs are in the shared packet:

```text
synthetic_data/customer_packets/demo_geocoded_loan/loan_application.pdf
synthetic_data/customer_packets/demo_geocoded_loan/pay_statement_novereign_systems.pdf
```

Select the two existing files, create the application, upload both PDFs and wait
for received status/byte counts, then select **Start processing**. Files can also
be selected after creation. No application ID is searched in the PDF text;
intake and upload establish the association through returned IDs. The same PDFs
can be reused for another new application without modification.

The packet's `application.json` supplies form defaults, not file bytes or runtime
IDs. Deploy the updated ingest and review services (`document-review-v2`) before
using this path. The GUI keeps DEFERRED creation and explicit release; the CLI
smoke script selects AUTO and dispatches after its uploads. See the
[packet README](../../synthetic_data/customer_packets/demo_geocoded_loan/README.md)
for `--application-file` and the optional manual-review variant.

Deploy the updated `azn-server` and BFF and sign in again to obtain
`cloudbank.write` before using mutations. Deploy the updated loan service too
to reconcile repeated start requests during dispatch/retry. The nine-tab
workspace and the architecture explorer remain in the
separate mock demo. Start that mode with:

```bash
cd src/cloudbank_ui
VITE_DATA_MODE=mock npm run dev
```

`npm test` verifies creation/upload/start adapters, safe errors, retry headers,
and unambiguous file/document association.
`npm run build` checks TypeScript and builds the SPA. `npm run preview` serves
the build locally. Neither command requires the cluster.

## Live manual review

Open **Manual review** in the main navigation. **Refresh queue** reads pending
CloudBank version-1 HUMAN tasks belonging to applications authorized for your
session. Select a task on the left to fetch its current details and completion
fields. The outcome select contains `APPROVED` and `REJECTED`; reason and policy
section are editable and start with the defaults from `complete-manual-review.sh`.
Reviewer identity and the required `UNDERWRITER` role are read-only; the BFF
derives the audit principal from the signed session, never from form input.

Select **Complete review** to submit. Acceptance removes the task from the queue
on refresh and shows an asynchronous confirmation; it does not display the human
request as a final lending outcome. The workflow refreshes authorization and
re-applies deterministic decision rules. The application list remains the current
live progress view; workspace evidence and AI result composition remain planned.
Task detail currently shows safe evidence reference IDs only.

The deployed BFF must have its server-side MicroTx configuration. Completion also
requires `ROLE_UNDERWRITER` in the signed user roles plus `cloudbank.write`.
The current `azn-server` demo bootstrap creates the administrator with the
explicit UNDERWRITER grant and adds missing baseline roles on later startup.
For older installations, redeploy the updated authorization server. Use a fresh
login in a private browser window afterward to refresh both authorization-server
and BFF sessions. ADMIN alone still does not imply underwriting for other users.
See the [deployment instructions](../../deploy/obaas/gateway-bff-runbook.md#human-task-support).
No UI field validation is introduced; backend errors stay visible. Retry an
uncertain request with the same fields; the logical operation key is retained.

## Licenses

Direct and indirect external libraries are limited to **MIT** or
**Apache-2.0**. Run `npm run check:licenses` after updating the lockfile.
`picocolors` and `source-map-js`, indirect PostCSS dependencies with other
licenses, are replaced by small original CloudBank modules under `vendor/`,
licensed **UPL-1.0** with the application. The source-map replacement disables
CSS source maps, which this GUI does not use.
