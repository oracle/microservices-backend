# Deploy `azn-server` on OCI OBaaS

This runbook covers only the initial `.env` configuration, the unified
`azn-server` deployment command, and the authenticated MicroTx Workflow Console
login test.

`azn-server` remains an internal `ClusterIP` service. The deployment does not
create an Ingress or expose `/user/api/v1*` to browsers.

## 1. Configure `.env`

Create `.env` in the `cloudbank-v6` directory root before running the deployment script. Add
only the following inputs:

```dotenv
OCI_REGION=<oci-region-identifier>
OKE_CLUSTER_OCID=<oke-cluster-ocid>
CLOUDBANK_KUBECONFIG_PATH=<absolute-path-to-a-dedicated-kubeconfig>
OCI_COMPARTMENT_OCID=<ocir-repository-compartment-ocid>
OCI_IDENTITY_NAME=<exact-username-accepted-by-ocir-login>
OCI_AUTH_TOKEN=<oci-auth-token>
OBAAS_RELEASE=<installed-obaas-helm-release-name>
MICROTX_NAMESPACE=<namespace-containing-obaas-and-azn-server>
MICROTX_PUBLIC_HOST=localhost
MICROTX_PROTOCOL=http
MICROTX_PUBLIC_PORT=5002
IMAGE_PULL_SECRET=cloudbank-ai-ocir-pull
POLICY_SERVICE_ACCOUNT=policy-retrieval-service
POLICY_OCI_GENAI_EMBEDDING_MODEL=<on-demand-embedding-model-id>
AI_SERVICE_ACCOUNT=ai-agent-service
AI_OCI_GENAI_CHAT_MODEL=<on-demand-chat-model-id>
OKE_CLUSTER_COMPARTMENT_ID=<oke-cluster-compartment-ocid>
GEOGRAPHIC_RISK_LOG_GEOCODING_DETAILS=false
```

Use these sources for the values:

- `OCI_REGION`: open **Developer Services → Kubernetes Clusters (OKE)** in the
  OCI Console, select the cluster on which OBaaS is installed, and use its
  region identifier, for example `eu-frankfurt-1`.
- `OKE_CLUSTER_OCID`: on the same cluster page, select **Access Cluster**, then
  **Local Access**, and copy the cluster OCID from the generated OCI CLI
  command.
- `CLOUDBANK_KUBECONFIG_PATH`: choose an absolute path outside this repository
  for the dedicated kubeconfig, for example
  `/Users/<local-user>/.kube/cloudbank-ai-obaas.yaml`.
- `OCI_COMPARTMENT_OCID`: use the OCID of the compartment in which the private
  `cloudbank-ai/azn-server` OCIR repository must be created.
- `OCI_IDENTITY_NAME`: use the complete username accepted by a working OCIR
  login. Do not prepend the OCIR namespace unless it is part of that username.
- `OCI_AUTH_TOKEN`: in the OCI Console, open the user profile, select
  **Auth tokens**, choose **Generate token**, enter a description, generate the
  token, and copy it immediately. Store the auth token, not the OCI Console
  password, in `.env`.
- `OBAAS_RELEASE`: use the exact Helm release name of the existing OBaaS
  installation, normally `obaas`. Verify it with `helm list --all-namespaces`.
- `MICROTX_NAMESPACE`: use the namespace containing both the OBaaS release and
  `azn-server`, for example `<CLOUDBANKAI_NAMESPACE>`.
- `MICROTX_PUBLIC_HOST`, `MICROTX_PROTOCOL`, and `MICROTX_PUBLIC_PORT`: keep the
  documented `localhost`, `http`, and `5002` values. They describe the
  local-only Workflow Console port-forward and must not expose MicroTx publicly.
- `IMAGE_PULL_SECRET`: use the Kubernetes Secret name shared by `azn-server`
  and the CloudBank services for private OCIR access. The documented default is
  safe across different OBaaS namespaces because Kubernetes Secret names are
  namespace-scoped. An existing Secret in the same namespace must be of type
  `kubernetes.io/dockerconfigjson` and authorize the configured OCIR registry.
  The script refreshes this Secret from `OCI_IDENTITY_NAME` and `OCI_AUTH_TOKEN`
  on every run, including when it already exists. Credentials are embedded in
  the Docker config for Kubernetes, without relying on Docker Desktop's host
  credential helper. `redeploy` still requires the Secret to exist.
- `POLICY_SERVICE_ACCOUNT` and `AI_SERVICE_ACCOUNT`: use the exact Kubernetes
  ServiceAccount names referenced by the OCI Workload Identity policies. Keep
  the documented defaults unless the corresponding IAM policy uses different
  names.
- `POLICY_OCI_GENAI_EMBEDDING_MODEL`: use an on-demand embedding model available
  in `OCI_REGION`.
- `AI_OCI_GENAI_CHAT_MODEL`: use an on-demand chat model available in
  `OCI_REGION`.
- `OKE_CLUSTER_COMPARTMENT_ID`: use the compartment OCID shown on the OKE
  cluster details page. This is the authorization scope used by both OCI GenAI
  Workload Identity policies; it is not necessarily `OCI_COMPARTMENT_OCID`,
  which scopes the OCIR repositories.
- `GEOGRAPHIC_RISK_LOG_GEOCODING_DETAILS`: keep `false`. Set it to `true` only
  for a short, controlled diagnostic because the resulting logs can identify
  a person or location; restore `false` immediately after the test.

Protect the file:

```bash
chmod 600 .env
```

Do not print, commit, or paste `.env` contents into commands, logs, screenshots,
or documentation.

During `first-deploy`, the unified script runs:

```bash
cd ./cloudbank-v6
run-compose.sh init --schema-profile runtime
```

`init` requires the pre-created `.env`. It preserves only the eighteen deployment
inputs listed above, replaces any other existing variables with newly generated
CloudBank configuration, adds every missing generated variable, and creates the
persistent signing-key pair when it does not already exist. For the OKE
deployment profile, it sets the generated OCI authentication selectors to
`WORKLOAD_IDENTITY` without adding OCI configuration files or private keys.

The generated configuration includes
`AZN_ISSUER_URI=http://localhost:8080`,
`AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET`, and the bootstrap administrator
password. Do not add duplicate values for those variables. The unified MicroTx
security script reads them directly from `.env` and never displays their values.

## 2. Run the unified deployment

The enabled demo-user bootstrap provisions `obaas-admin` with
`ROLE_ADMIN,ROLE_CONFIG_EDITOR,ROLE_USER,ROLE_UNDERWRITER` on a new database.
The normal first deployment therefore includes the grant needed to complete
HUMAN tasks in the GUI. On an existing database, the updated authorization-server
image adds missing baseline roles at startup, preserving the identity, password
hash and additional grants. Repeated startup makes no further role updates once
the baseline is complete. No separate `changeRole` command is needed.
After upgrading an existing installation, use a fresh authorization-server/BFF
login (for example a private browser window) to obtain the updated signed roles.

The workstation must provide the OCI CLI, `kubectl`, Helm, Docker with Buildx
and Compose, `jq`, OpenSSL, and `curl`. OCI CLI authentication must already work
for the configured identity and target tenancy.
The existing OBaaS release must have its MicroTx coordinator, Console, and
Workflow Server enabled; the unified helper checks these resources before
building or publishing an image.

Generate a unique immutable image tag in the current shell:

```bash
export NEW_IMAGE_TAG="first-$(date -u +%Y%m%d%H%M%S)"
```

Run the first deployment from the repository root:

```bash
cd ./cloudbank-v6
./deploy/obaas/deploy-azn-server_v1.sh first-deploy
```

The script obtains the OKE kubeconfig, detects the single OBaaS target at
version 2.1.0 or later, initializes the local CloudBank configuration, creates
or verifies the private OCIR repository and image-pull Secret, builds and pushes
the `azn-server` image,
and performs the Helm lint/render dry run. It then displays the resolved target
and asks whether to continue with deployment and MicroTx OIDC configuration. Answer `y` only after
reviewing that output.

After deployment, the same script displays the OCIR and Kubernetes results,
verifies the Deployment, Service, EndpointSlice, and Secret metadata, and checks
the health endpoint, issuer metadata, and JWKS. Helm uses
`AZN_ISSUER_URI=http://localhost:8080` from the first deployment; in-cluster
token/JWKS URLs remain separate. The script then invokes the MicroTx security
helper, waits for Azn and bridge readiness before starting the Console, checks
its browser redirect, and verifies authenticated Workflow API access. It finishes with:

```text
SUCCESS: azn-server first-deploy completed and all verification checks passed.
```

For a later re-deploy, keep `.env` and the signing keys unchanged, generate a
new tag, and run:

```bash
export NEW_IMAGE_TAG="release-$(date -u +%Y%m%d%H%M%S)"
cd ./cloudbank-v6
./deploy/obaas/deploy-azn-server_v1.sh redeploy
```

The re-deploy preserves the existing CloudBank application Secrets and rejects
the currently deployed image tag. It preserves the configured issuer and
automatically reapplies MicroTx security using the same deployment confirmation.
Changing the issuer of an existing deployment requires a coordinated migration;
the Helm helper refuses to change it silently. Existing CloudBank services and
BFF must validate that same issuer. The security helper reports stale validators
instead of reporting successful authentication with inconsistent consumers.
After pod replacement, restart local Azn/Console port-forwards.

The script provisions the BFF OAuth client keys in `cloudbank-ai-azn-auth`
automatically. On first deployment it creates them; on redeploy it adds either
missing key without replacing existing non-empty values. The confidential
client secret is generated unless
`AZN_AUTHORIZATION_SERVER_BFF_CLIENT_SECRET` already exists in `.env`. The
redirect URI comes from `BFF_CALLBACK_URI` in `.env` when present, otherwise
it defaults to `http://127.0.0.1:5173/bff/auth/callback`. Redeploying
`azn-server` once after this change registers the client in the running pod;
the [BFF runbook](gateway-bff-runbook.md) needs no manual Secret patch.
