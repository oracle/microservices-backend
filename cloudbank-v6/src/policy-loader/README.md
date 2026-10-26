# One-Shot Policy Loader on OBaaS / OKE

`policy-loader` loads the versioned corpus from `synthetic_data/policy` into
the Oracle tables used by `policy-retrieval-service`. It runs as a Kubernetes
`Job`, exits after loading, and exposes no ports or APIs.

This is a **delta guide**. Before using it, complete the standard process
described in [`deploy/obaas/services-runbook.md`](../../deploy/obaas/services-runbook.md).
That runbook remains the sole operational source for kubeconfig, OBaaS, the ADB
wallet, OCIR, `azn-server`, OCI GenAI, the embedding model, and OKE Workload
Identity. Those activities must not be repeated for the loader.

## What the Loader Adds

The new flow adds only:

- the `policy-loader` Maven module and corresponding image, which contains an
  immutable copy of the corpus;
- `policy-embedding-support`, shared with `policy-retrieval-service`, so loading
  and query execution use the same OCI GenAI implementation;
- the `CB_POLICY_CORPUS_LOAD` control table;
- the `CB_POLICY_LOADER_APP` user and `CB_POLICY_LOADER_RUNTIME` role, limited
  to `SELECT` and `INSERT` on the three corpus tables;
- a dedicated database Secret and a temporary Kubernetes Job.

The Job uses the same Kubernetes ServiceAccount configured for
`policy-retrieval-service` and receives the same region, compartment, and model
`OCI_GENAI_*` values from the script. Therefore, **no second IAM policy,
dynamic group, or new Workload Identity is required**. If the retrieval
service runbook prerequisites have already been satisfied, there are no
additional IAM activities.

## Automated Deployment Execution

Do not apply a separate manifest or manually create users or Secrets. The
updated [`deploy-services.sh`](../../deploy/obaas/deploy-services.sh) already
performs these steps in order:

1. Builds and publishes the `policy-loader` image together with the other
   CloudBank images.
2. Creates only the loader database Secret if it is missing, without
   displaying its value.
3. Migrates the schema, creates the account, and assigns the role.
4. Creates or verifies the ServiceAccount already owned by the
   `policy-retrieval-service` Helm release.
5. Runs and waits for the `cloudbank-policy-loader-<checksum-tag>` Job.
6. Starts or updates the normal Deployments only after loading succeeds.

For an existing environment, use the standard `redeploy` process documented in
the runbook. The script generates the new immutable tag, recognizes the
previous database Secret set and creates only missing per-service Secrets,
including the loader and decision identities. It does not rotate or replace
existing Secrets.

The integrated preflight validates the ServiceAccount and Job manifest before
the script asks for confirmation. It does not generate credentials, publish
images, or load data during that preflight.

## Loading Contract

The loader reads `policy_corpus_manifest.json` and the Markdown files listed
in the manifest. Each `## S<n>.` section becomes a chunk with a stable ID. For
the current corpus, the expected result is:

| Item | Expected value |
| --- | ---: |
| Corpus | `POLICY-CORPUS-2026.0` |
| Version | `2026.0` |
| Documents | 9 |
| Chunks | 73 |

Before writing data, the Job calculates a SHA-256 digest over the manifest and
documents and generates every embedding through OCI GenAI. The documents,
chunks, and control record are then inserted in a single transaction. An error
does not leave a partial load.

Execution is strictly idempotent:

- same corpus, digest, model, dimensions, and counts: exits successfully
  without invoking the model or rewriting data;
- populated tables without a corresponding `CB_POLICY_CORPUS_LOAD` record:
  exits with an error;
- corpus, model, or dimensions different from the recorded load: exits with
  an error.

These safeguards prevent vectors produced by different models from being
mixed. Changing the corpus or model requires an explicit, reviewed migration;
the Job never deletes or overwrites existing policies.

## Additional Loader-Only Verification

The deployment command already waits for the Job to complete. If a separate
check is needed, without reading Secrets:

```bash
KUBECONFIG_PATH="$(awk -F= '$1 == "CLOUDBANK_KUBECONFIG_PATH" { print substr($0, index($0, "=") + 1) }' .env)"
NAMESPACE="$(awk -F= '$1 == "MICROTX_NAMESPACE" { print substr($0, index($0, "=") + 1) }' .env)"
CONTEXT="$(KUBECONFIG="$KUBECONFIG_PATH" kubectl config current-context)"

KUBECONFIG="$KUBECONFIG_PATH" kubectl --context "$CONTEXT" -n "$NAMESPACE" get jobs \
  -l app.kubernetes.io/name=policy-loader \
  -o custom-columns=NAME:.metadata.name,SUCCEEDED:.status.succeeded,FAILED:.status.failed
```

For the most recent Job, `SUCCEEDED` must be `1`, and `FAILED` must be empty or
`0`. The Job has a one-hour TTL; its absence after successful completion does
not indicate an error.

The existing `policy-retrieval-service` verification continues to cover
authorization and result limits. Validation of the 9 documents and 73 chunks
is instead part of the loader transaction: the Job does not complete
successfully if the persisted counts or embeddings do not match. No gateway
route or new HTTP check is needed for the loader because it is not a network
service.

## Additional Manual Operations, Only After a Failure

A normal deployment requires no loader-specific manual operations. If the Job
fails:

1. Preserve the Job name and status, and read the sanitized summary produced
   by `deploy-services.sh`; do not decode Secrets or copy credentials into
   logs.
2. Correct the reported cause, typically OCI authorization that has not yet
   propagated, an unavailable model, an ADB connection error, or legacy state
   in the policy tables.
3. Follow the standard `redeploy` process; the helper creates a new immutable
   tag.

Only when resuming an interrupted `first-deploy`, and the failed Job still
exists, collect its status and events, delete only that temporary Job, and
rerun `first-deploy`. Use the `KUBECONFIG_PATH`, `CONTEXT`, and `NAMESPACE`
values derived from `.env` in the verification example above:

```bash
KUBECONFIG="$KUBECONFIG_PATH" kubectl --context "$CONTEXT" -n "$NAMESPACE" delete job \
  '<exact-cloudbank-policy-loader-job-name>'
```

Do not delete Secrets, accounts, roles, or tables. In particular, stop if the
loader reports existing data without `CB_POLICY_CORPUS_LOAD`: this may be a
legacy load. Reconciling or removing that data requires an approved database
migration and is outside the one-shot Job's scope.

## Security Boundaries

- The loader does not receive the privileged OBaaS Secret, the schema-owner
  Secret, or OAuth Secrets.
- The ADB wallet is mounted read-only.
- The container runs as non-root, has no Linux capabilities, and uses a
  read-only root filesystem.
- Policy text, vectors, and credentials are not written to logs.
- `policy-retrieval-service` remains read-only; a write API is not part of its
  runtime contract.
