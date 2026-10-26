# Lab owner application visibility

The OKE lab uses one interactive account, `obaas-admin`. It can see every loan
application, including applications created by component smoke tests or other
service identities. New applications are covered automatically by its active
`ADMIN` grant; no per-application assignment is required.

## Automatic deployment

Both `deploy-services.sh first-deploy` and `deploy-services.sh redeploy`:

1. verify the configured issuer and resolve exactly one `obaas-admin` with
   `ROLE_ADMIN` through the internal authorization-server admin API;
2. complete the schema bootstrap;
3. run `provision-lab-admin.sh` with the published schema-init image;
4. continue with the policy loader and service deployment only after the
   application-visibility check succeeds.

The bootstrap uses the account's persistent `cb_principal_id`, issuer, and
subject. It creates the missing `CB_APP_PRINCIPAL` row and `ADMIN` grant in
`CB_APP_ROLE_GRANT`. Repeated runs preserve existing valid rows. An inactive
principal, revoked/expired grant, or identity mismatch stops deployment and
requires explicit reconciliation; the helper does not reverse those decisions.

The existing ownership, role, and per-application grant checks remain in force.
Other identities receive no additional access. Future versions can add users
with restricted visibility using the same model. This version adds no profile
switcher or extra interactive user setup.

## Repair an existing installation

From the repository root, with the existing protected `.env`:

```bash
cd ./cloudbank-v6
./deploy/obaas/provision-lab-admin.sh --check-identity
./deploy/obaas/provision-lab-admin.sh
```

The second command displays the target and asks for confirmation. It reuses the
published `cloudbank-schema-init` image with the installed loan-service tag.
If those tags differ, supply `--image <published-schema-init-image:immutable-tag>`.
No image rebuild, application restart, or new browser login is required.

Successful output includes:

```text
LAB_ADMIN_APPLICATIONS_TOTAL=<count>
LAB_ADMIN_APPLICATIONS_VISIBLE=<same-count>
LAB_ADMIN_BOOTSTRAP_OK
```

Refresh **Loan Applications** and select **All statuses**. A fresh unseeded
installation may correctly report zero applications until the first intake.
The grant makes stored applications visible; it does not import standalone
MicroTx executions as loan applications.

## Privilege and verification

A temporary Kubernetes Job uses the existing OBaaS database bootstrap Secret
and wallet. Its SQL is versioned in
[`003-lab-admin-access.sql`](../../src/schema/admin/003-lab-admin-access.sql).
The Job verifies the same visibility predicate used by the loan repository
before committing. Runtime service database privileges are unchanged.
Temporary Job, ConfigMap, and identity-metadata Secret are removed on exit;
credentials, tokens, and identity details are not printed.

Run the shell regression tests and, against a configured lab, the Oracle
regression tests:

```bash
cd ./cloudbank-v6
bash ./deploy/obaas/tests/test-lab-admin-bootstrap.sh
bash ./deploy/obaas/tests/test-lab-admin-oracle.sh
```

The Oracle suite checks provisioning, idempotency, inactive/revoked/expired
guards, identity mismatch, and preservation of other principals. Its database
changes are rolled back. It still creates temporary Kubernetes test resources.
