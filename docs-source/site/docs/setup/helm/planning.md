---
title: Planning your installation
sidebar_position: 2
---

Before embarking on installation, there are a few decisions you should make. 

The main steps of the planning process are as follows:

- Choose database deployment option
- Choose cluster access option
- Choose components
- Plan any customizations
- Confirm prerequisites met
- Perform installation

Each step is explained in detail below.

## Choose database deployment option

An Oracle database is a prerequisite for installation, but you may use any kind of database deployment.  For example, you may choose to use: 

- Oracle Autonomous AI Database
- Oracle Globally Distributed Autonomous AI Database
- Oracle AI Database running in Base Database Service
- Oracle AI Database running in a container inside your Kubernetes cluster
- Oracle AI Database running in your own data center or cloud provider

You will need to provide various configuration information to the Helm charts during installation depending on where your database will be deployed.  In each case, you will specify this information in the `database` section of the `values.yaml` file for the `obaas` Helm chart. 

| Type of deployment | Information you will need |
| --- | --- | 
| Autonomous AI Database (including Globally Distributed) | The OCID of your database, your OCI CLI or SDK configuration details, including your private key, and the password for your `ADMIN` user. | 
| In-cluster (Single Instance) deployment | The username and password for both an admin user, e.g., `SYSTEM`, and a user for OBaaS, e.g., `OBAAS_USER`. | 
| Any other type of deployment | The username and password for both an admin user, e.g., `SYSTEM`, and a user for OBaaS, e.g., `OBAAS_USER`, and the connection details for your database (host, port, service name). | 

Ensure that you review the installation documentation and the instructions in the example `values.yaml` file provided for your specific type of database deployment and provide the necessary configuration information.  Also, ensure that you create Kubernetes secrets with your database credentials if required for your chosen deployment option.

:::note
If you plan to use the in-cluster (Single instance) deployment option, be aware that you will need to have adequate storage on your nodes for the database files.  We recommend 250 GB ephemeral node storage for this option.
:::

## Choose cluster access option

Kubernetes has deprecated the Ingress API and is moving to the Gateway API as its replacement.  At this time, both are supported, but it is important to consider your migration stragegy.

OBaaS 2.1.0 includes both NGINX Ingress Controller (which works with the Ingress API) and Envoy Gateway (which works with the Gateway API).  You should choose which of these you wish to install, and update the `values.yaml` for the `obaas` Helm chart to reflect your choice.  You can choose which is installed by setting the appropriate `enabled` field to `true` or `false`.  Note that there are additional configuration options for each.

```yaml
gateway-helm:
  enabled: true

  ...

ingress-nginx:
  enabled: true
```

You may also choose to install both if you prefer, or neither, for example, if your Kubernetes cluster already has another method for external cluster access provided.

Additional resources are likely to be available from your Kubernetes provider.  For example, see [this guide](https://gateway-api.sigs.k8s.io/guides/getting-started/migrating-from-ingress-nginx/) on the Kubernetes SIG website.

## Choose components

OBaaS contains a number of components, and you may choose which components you wish to install.  Each component has it's own section in the `values.yaml` file for either the `obaas` or `obaas-prereqs` Helm chart.  Note that the components in the `obaas-prereqs` Helm chart are cluster-wide deployments that can only be installed once per cluster.

You may opt out of installing any component by setting its `enabled` field to `false`.  For example, if you do not want to install the Strimzi Kafka Operator, you would update the `values.yaml` for the `obaas` Helm chart as follows:

```yaml
kakfa:
  enabled: false
```

Note that most components also have additional configuration, and some have optional sub-components that you may also enable or disable as desired.

## Plan any customizations

The OBaaS Helm charts include most components by depending on those components' public Helm charts.  This means that any customization option provided in those Helm charts are available for your use. 

For example the [APISIX Helm chart](https://github.com/apache/apisix-helm-chart/tree/apisix-2.12.3/charts/apisix) provides many configuration options that are documented by APISIX. 

If you wish to use a customization option from a dependent chart, you may specify it under the key/section for that chart in the appropriate `values.yaml`.  For example, suppose you wanted to change the admin port for APISIX.  In the documentation for the APISIX Helm chart, you notice they provide a field called `apisix.admin.port` for this purpose.  You can include this in the `values.yaml` for the `obaas` Helm chart under the `apisix` key, as follows:

```yaml
apisix:
  apisix:
    admin:
      port: 9123
```

In the *Platform Services* section of this documentation, you will find details of commonly used customizations.

## Confirm prerequisites met

As a final step, before starting the installation, please take a moment to confirm that your environment meets the stated [prerequisites](./prereqs.md) as many common installation problems are caused by failure to ensure the environment meets the prerequisites.

## Perform Installation

You are now ready to continue to the [installation guide](./install.md).
