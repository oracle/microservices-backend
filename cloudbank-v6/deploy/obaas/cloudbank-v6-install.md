# CloudBankAI v6 Install Guide.

## 1 OBaaS setup on OKE and test
- install OBaaS on OKE as `<CLOUDBANKAI_NAMESPACE>` following [here](https://oracle.github.io/microservices-backend/obaas/docs/setup/)

- from ORM Job Output, copy the `kubeconfig_cmd` value, and run it in a terminal.

- Check MicroTx Workflow Console without auth:

```bash
export KUBE_CONTEXT="$(kubectl config current-context)"
export MICROTX_NAMESPACE='<CLOUDBANKAI_NAMESPACE>'

kubectl --context "$KUBE_CONTEXT" --namespace "$MICROTX_NAMESPACE" \
  port-forward --address 127.0.0.1 service/obaas-otmm-console 5002:5002
```

- Open a private broswer on: http://localhost:5002/consoleui/ to access MicroTx web console.

- start rancher deskop or equivalent for docker

## 2.1 Step-by-Step Deployment  

- [Azn-server deploy guide](../../deploy/obaas/azn-server-runbook.md)

- [MicroTx azn-server authentication setup](../../deploy/microtx/oke-obaas/secure-microtx-azn.md)

- [Cloudbank AI services deployment](../../deploy/obaas/services-runbook.md)

- [MicroTx cloudbank-loan-origination workflow deploy](../../src/workflows/cloudbank-loan-origination/README.md#1-obaas-oke-deployment)

- [Backend for Front-end API](../../deploy/obaas/gateway-bff-runbook.md)

## 2.2 One-Shot Deployment

### 2.2.1 Setup pre-launch (OCI)

The existing OBaaS release must be version 2.1.0 or later, with its MicroTx
coordinator, Console, and Workflow Server enabled. OCI CLI authentication must
already work for the configured identity and target tenancy. The OCI identity
may inspect the OKE cluster and create/read private OCIR repositories in
`OCI_COMPARTMENT_OCID`.

The workstation must provide the OCI CLI, `kubectl`, Helm 3.8 or newer (including
Helm 4), Docker with Buildx and Compose, `jq`, OpenSSL, `curl`, `patch`, and Maven.
Docker can build for the OKE node architecture, obtain the base images used
by the root `Dockerfile`, and publish to OCIR.

Create `.env` in the `cloudbank-v6` directory before running the deployment script. Add
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

`policy-retrieval-service` and `ai-agent-service` call OCI Generative AI through
OKE Workload Identity. Their Pods do not receive an OCI configuration file,
API key, user private key, or dynamic-group identity. The policy loader reuses
the policy-retrieval ServiceAccount, so it needs no additional IAM policy.

Ask an IAM administrator to create these statements once in the compartment
identified by `OKE_CLUSTER_COMPARTMENT_ID`. Go in **Identity & Security**/**Policies**, and create two policies, replacing the placeholders with the matching values already stored in `.env`:

```text
Allow any-user to use generative-ai-text-embedding in compartment id <oke-cluster-compartment-ocid> where all {
  request.principal.type = 'workload',
  request.principal.namespace = '<obaas-application-namespace>',
  request.principal.service_account = 'policy-retrieval-service',
  request.principal.cluster_id = '<oke-cluster-ocid>'
}
```

```text
Allow any-user to use generative-ai-chat in compartment id <oke-cluster-compartment-ocid> where all {
  request.principal.type = 'workload',
  request.principal.namespace = '<obaas-application-namespace>',
  request.principal.service_account = 'ai-agent-service',
  request.principal.cluster_id = '<oke-cluster-ocid>'
}
```

The namespace must equal `MICROTX_NAMESPACE`; the cluster and compartment values
must equal `OKE_CLUSTER_OCID` and `OKE_CLUSTER_COMPARTMENT_ID`. 
The selected embedding and chat models must be on-demand models available in `OCI_REGION`.

OKE Workload Identity uses the `workload` principal directly. Do not create a
dynamic group and do not add an OCI key or config-file mount. See Oracle's
[Granting Workloads Access to OCI Resources](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contenggrantingworkloadaccesstoresources.htm).

The OCI IAM policies must exist and have propagated before running the script.

### 2.2.2  Run the deployment

You must have **Docker** configured on your laptop. Then run the first deployment from the repository root in this way:

```bash
export NEW_IMAGE_TAG="first-$(date -u +%Y%m%d%H%M%S)"
cd ./cloudbank-v6
./deploy/obaas/cloudbankai_deploy.sh first-deploy
```

The command deploys `azn-server` and automatically enables and verifies MicroTx
authentication, deploys the remaining CloudBank services, and deploys the
`cloudbank-loan-origination` workflow version 1 with its task definitions.
Review the resolved deployment plans and answer `y` only when the target is
correct. During workflow deployment, complete the existing OAuth + PKCE
operator flow:

Open the generated authorization URL in a new private browser window, sign in
as `obaas-admin` or `obaas-config`, and paste only the one-time `code` value at
the hidden terminal prompt. A `404` on the manual callback is expected. Do not
reuse or share the callback URL.

If the first deployment stops at `[2/3]` after `azn-server` completed, resume
from the services step, from the `cloudbank-v6` directory:

```bash
./deploy/obaas/cloudbankai_deploy.sh first-deploy --from services
```

This checks that the existing `azn-server` Deployment is ready, then runs the
services and workflow steps. It does not require a new `NEW_IMAGE_TAG` for Azn.
If services completed and only `[3/3]` failed, use `--from workflow` instead.
For an update of existing services, use `redeploy` with the same `--from` option.

### 2.2.2.1 Backend for Front-end API

To deploy the BFF or upgrades only the `gateway-bff-service` Helm release
and its own private OCIR image repository, follow the instruction here: [runbook](../../deploy/obaas/gateway-bff-runbook.md).

### 2.2.3 Post-launch: setup ADB

From OCI Web console add your IP address to the `Access control list` to use the SQL ADB console. As admin from OCI Web console:

```sql
EXEC SDO_GCDR.ELOC_GRANT_ACCESS('CB_GEOGRAPHIC_RISK_APP');
```

## 3. Access to the environment

- Workflow/Services Test:

	- Terminal 1: CloudBank Azn (`http://localhost:8080`):

	```bash
	export KUBE_CONTEXT="$(kubectl config current-context)"
	export MICROTX_NAMESPACE='<CLOUDBANKAI_NAMESPACE>'

	kubectl --context "$KUBE_CONTEXT" --namespace "$MICROTX_NAMESPACE" \
	port-forward --address 127.0.0.1 service/azn-server 8080:8080
	```

	- Terminal 2: MicroTx Console (`http://localhost:5002/consoleui/`):
  
	```bash
	export KUBE_CONTEXT="$(kubectl config current-context)"
	export MICROTX_NAMESPACE='<CLOUDBANKAI_NAMESPACE>'

	kubectl --context "$KUBE_CONTEXT" --namespace "$MICROTX_NAMESPACE" \
	port-forward --address 127.0.0.1 service/obaas-otmm-console 5002:5002
	```
	
	- Terminal 3: MicroTx Workflow Server (`http://localhost:9010/workflow-server/api`):

	```bash
	export KUBE_CONTEXT="$(kubectl config current-context)"
	export MICROTX_NAMESPACE='<CLOUDBANKAI_NAMESPACE>'

	kubectl --context "$KUBE_CONTEXT" --namespace "$MICROTX_NAMESPACE" \
	port-forward --address 127.0.0.1 service/obaas-otmm-workflow-server 9010:9010
	```

	- Terminal 4: MicroTx transaction coordinator (`http://localhost:9000`):

	```bash
	export KUBE_CONTEXT="$(kubectl config current-context)"
	export MICROTX_NAMESPACE='<CLOUDBANKAI_NAMESPACE>'

	kubectl --context "$KUBE_CONTEXT" --namespace "$MICROTX_NAMESPACE" \
	port-forward --address 127.0.0.1 service/obaas-otmm-tcs 9000:9000
	```
- Connect to MicroTx Web Console

	- Open an incognito browser on: http://localhost:5002/consoleui/

	- Provide `obaas-admin`/**<AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD>** you'll find in `.env` file.


  

