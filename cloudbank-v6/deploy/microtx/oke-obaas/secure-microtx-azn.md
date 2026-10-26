# Secure MicroTx with CloudBank Azn

This procedure configures authentication between the existing CloudBank
`azn-server` and the MicroTx components installed by an OBaaS Helm release at
version 2.1.0 or later on OKE. All services remain private. Browser and operator
access uses only port-forwards bound to `127.0.0.1`; the procedure creates no
Ingress, public load balancer, or second MicroTx installation.

The script patches the live Azn and MicroTx resources. It does not run
`helm upgrade obaas`, deploy workflow definitions, or print OAuth secrets and
access tokens.

## Prerequisites

1. Complete Chapter 1 of
   [`azn-server-runbook.md`](../../obaas/azn-server-runbook.md). The
   `.env` in `cloudbank-v6` directory must contain the documented OBaaS release, namespace,
   local Console endpoint, and kubeconfig inputs.
2. Deploy `azn-server` with
   `./deploy/obaas/deploy-azn-server_v1.sh first-deploy`.
3. Install `kubectl`, Helm, `jq`, OpenSSL, and `curl` on the workstation.

Do not source `.env` into the shell. It contains credentials. The security
script reads only the required values without displaying them.

## Enable Authentication

The unified `deploy-azn-server_v1.sh` command runs this step automatically after
both `first-deploy` and `redeploy`, using its deployment confirmation. For a
standalone repair, run from the repository root:

```bash
cd ./cloudbank-v6
./deploy/microtx/oke-obaas/secure-microtx-workflows.sh --enable
```

The command performs the following sequence:

1. reads the kubeconfig, OBaaS release, namespace, local endpoint settings, and
   generated Workflow OAuth credential from `.env`;
2. confirms that the selected Helm release is OBaaS 2.1.0 or later and that the
   required Azn and MicroTx resources exist;
3. compares encoded Secret values without decoding or printing credentials;
4. validates every Kubernetes patch with server-side dry run;
5. displays the resolved non-sensitive target and asks for confirmation;
6. synchronizes the Console OAuth Secret, preserving an existing Console cookie
   Secret;
7. checks that Azn and existing CloudBank services/BFF use `AZN_ISSUER_URI`
   from `.env`; it refuses to migrate the central issuer silently;
8. waits for Azn, then restarts and waits for the bridge, and checks its issuer
   and browser authorization endpoint before applying/restarting the Console;
9. verifies the actual Console redirect points to `http://localhost:8080`,
   waits for the remaining workloads, and verifies an authenticated,
   non-mutating Workflow API worker request.

The Console loads OIDC discovery at startup. Waiting for Azn and the bridge
before configuring the Console prevents it from retaining an old cluster-only
authorization endpoint, including on the first deployment. `--enable --yes`
is available for the unified deploy script after that script's interactive
target confirmation; standalone use normally keeps the prompt.

The temporary verification port-forwards bind only to `127.0.0.1` and are
stopped automatically. A successful execution ends with:

```text
SUCCESS: MicroTx authentication is enabled and the authenticated Workflow API check passed.
```

## Test the Workflow Console login

From the `repository` root, read only the required non-secret values from `.env`
and start the port-forward in a dedicated terminal. Do not source the complete
file.

```bash
env_value() {
  awk -F= -v key="$1" \
    '$1 == key { print substr($0, index($0, "=") + 1) }' .env |
    tail -n 1
}

export KUBECONFIG="$(env_value CLOUDBANK_KUBECONFIG_PATH)"
export MICROTX_NAMESPACE="$(env_value MICROTX_NAMESPACE)"
export OBAAS_RELEASE="$(env_value OBAAS_RELEASE)"
export KUBE_CONTEXT="$(kubectl config current-context)"
unset -f env_value

kubectl --context "$KUBE_CONTEXT" --namespace "$MICROTX_NAMESPACE" \
  port-forward --address 127.0.0.1 \
  "service/${OBAAS_RELEASE}-otmm-console" 5002:5002
```

The Console redirects browser authentication to `http://localhost:8080`, so
the authorization server must also be available locally. Ensure port `8080`
is free: stop any local service or SSH tunnel occupying it, particularly one
pointing to a different authorization-server instance.

In a second dedicated terminal, from the `repository` root, repeat the environment setup above (through
the `test` commands), then start the authorization-server port-forward:

```bash
env_value() {
  awk -F= -v key="$1" \
    '$1 == key { print substr($0, index($0, "=") + 1) }' .env |
    tail -n 1
}

export MICROTX_NAMESPACE="$(env_value MICROTX_NAMESPACE)"
export KUBE_CONTEXT="$(kubectl config current-context)"
unset -f env_value

kubectl --context "$KUBE_CONTEXT" --namespace "$MICROTX_NAMESPACE" \
  port-forward --address 127.0.0.1 service/azn-server 8080:8080
```

Keep both port-forwards running throughout login and Console use: port `5002`
for the Console and port `8080` for the authorization server in the same cluster.

Open a new private browser window and sign in:

```yaml
browser: http://localhost:5002/consoleui/
username: obaas-admin
password: <value of AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD in .env>
```

Read the password from the protected local file with an approved
secret-handling method. Do not print it, paste it into shell history, or reuse a
previous `/oidc/redirect?code=...` URL.

## Reapply after an `azn-server` re-deploy

The Azn Helm deployment now uses the configured issuer from the first deployment
and preserves it on redeploy. The unified deployment automatically reapplies
MicroTx authentication and synchronizes its OAuth Secret. When using the
lower-level Helm helper directly, reapply this command after deployment:

```bash
cd ./cloudbank-v6
./deploy/microtx/oke-obaas/secure-microtx-workflows.sh --enable
```

An issuer migration requires a coordinated change to all JWT validators. If
the helper reports mismatched CloudBank deployments, redeploy the services
with `./deploy/obaas/deploy-services.sh redeploy`, then the BFF with
`./deploy/obaas/deploy-gateway-bff.sh deploy`, before repeating this helper.
Both deployment scripts check the live Azn issuer against `.env`. The existing
Console cookie Secret is preserved. Restart local Console/Azn port-forwards
after their pods are replaced, and begin a fresh browser login.

## Remove Authentication on azn

This is a development-recovery operation only. It permits anonymous access to
the MicroTx Workflow API and must not be used on a shared, staging, or
production installation.

```bash
cd ./cloudbank-v6
./deploy/microtx/oke-obaas/secure-microtx-workflows.sh --disable
```

The command first validates the removal patches and shows the selected target.
After confirmation, it disables authorization on the coordinator, Console, and
Workflow Server and verifies that representative anonymous routes reach the
Workflow API. It does not delete or disable the CloudBank `azn-server`, OIDC
bridge, or OAuth Secrets.

Restore protection with:

```bash
cd ./cloudbank-v6
./deploy/microtx/oke-obaas/secure-microtx-workflows.sh --enable
```
