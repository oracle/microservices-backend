---
title: "Setup"
description: "Setup Oracle Backend for Microservices and AI"
keywords: "setup install springboot spring development microservices development oracle backend"
resources:
  - name: oci-private-templates
    src: "oci-private-templates.png"
    title: "Oracle Cloud Infrastructure Private Templates"
  - name: oci-private-template-details
    src: "oci-private-template-details.png"
    title: "Private Template Details"
  - name: oci-private-template-download
    src: "oci-private-template-download.png"
    title: "Download Private Template"
  - name: oci-private-template-create-stack
    src: "oci-private-template-create-stack.png"
    title: "Create Stack from Private Template"
  - name: oci-private-template-create-stack-info
    src: "oci-private-template-create-stack-info.png"
    title: "Create Stack Wizard Information"
  - name: oci-private-template-create-stack-config
    src: "oci-private-template-create-stack-config.png"
    title: "Create Stack Wizard Config Variables"
  - name: oci-private-template-create-stack-config-lb-vault
    src: "oci-private-template-create-stack-config-lb-vault.png"
    title: "Create Stack Wizard Config Variables"
  - name: oci-private-template-create-stack-config-review
    src: "oci-private-template-create-stack-config-review.png"
    title: "Create Stack Wizard Config Review"
  - name: oci-stack-plan
    src: "oci-stack-plan.png"
    title: "Create Stack Plan"
  - name: oci-stack-apply
    src: "oci-stack-apply.png"
    title: "Create Stack Apply"
  - name: oci-stack-apply-logs
    src: "oci-stack-apply-logs.png"
    title: "Create Stack Apply Logs"
  - name: oci-stack-additional-options
    src: "oci-stack-additional-options.png"
    title: "Create Stack Additional Options - Standard Edition"
  - name: oci-stack-oke-options
    src: "oci-stack-oke-options.png"
    title: "Create Stack OKE Options"
  - name: oci-stack-outputs
    src: "oci-stack-outputs.png"
    title: "Create Stack Outputs"
  - name: oci-stack-output-oke
    src: "oci-stack-output-oke.png"
    title: "Get Kube Config Cmd"
  - name: oci-stack-db-options
    src: "oci-stack-db-options.png"
    title: "Database Options"
  - name: oci-stack-byodb-options
    src: "oci-stack-byodb-options.png"
    title: "Bring your Own Database Options - Standard Edition"
  - name: oci-stack-app-name
    src: "oci-stack-app-name.png"
    title: "Compartment, Application and Edition"
  - name: ebaas-mp-listing
    src: "ebaas-mp-listing.png"
    title: "Marketplace Listing"
  - name: ebaas-stack-page1
    src: "ebaas-stack-page1.png"
    title: "Create Stack"
  - name: oci-stack-passwords
    src: "oci-stack-passwords.png"
    title: "Administrator Passwords"
  - name: oci-stack-lb-options
    src: "oci-stack-lb-options.png"
    title: "Load Balancer Options"
  - name: oci-stack-vault-options
    src: "oci-stack-vault-options.png"
    title: "Standard Edition"
  - name: azn-stack-app-info
    src: "azn-stack-app-info.png"
    title: "Access Information"
  - name: oci-stack-app-info
    src: "oci-stack-app-information.png"
    title: "Detailed Access Information"
  - name: oci-stack-network-options
    src: "oci-stack-network-options.png"
    title: "Network Options - Standard Edition"

---

Oracle Backend for Microservices and AI is available in the [OCI Marketplace](https://cloudmarketplace.oracle.com/marketplace/en_US/listing/138899911).

- [Prerequisites](#prerequisites)
- [OCI policies](#oci-policies)
  - [Oracle Container Engine for Kubernetes](#oracle-container-engine-for-kubernetes)
  - [VCN](#vcn)
  - [Container Registry](#container-registry)
  - [Object Storage](#object-storage)
  - [Autonomous Database](#autonomous-database)
  - [Vault](#vault)
    - [Additional Vault](#additional-vault)
  - [Oracle Resource Manager](#oracle-resource-manager)
- [Summary of Components](#summary-of-components)
- [Overview of the Setup Process](#overview-of-the-setup-process)
- [Set Up the OCI Environment](#set-up-the-oci-environment)
- [Set Up the Local Machine](#set-up-the-local-machine)
- [Access information and passwords from the OCI Console](#access-information-and-passwords-from-the-oci-console)

## Prerequisites

You must meet the following prerequisites to use Oracle Backend for Microservices and AI. You need:

- An Oracle Cloud Infrastructure (OCI) account in a tenancy with sufficient quota to create the following:

  - An OCI Container Engine for Kubernetes cluster (OKE cluster), plus a node pool with three worker nodes.

    - Each node should have 2 OCPUs and 32 GB of RAM.
    - 750GB of block volume storage with a `Balanced` performance level.

  - A virtual cloud network (VCN) with at least two public IP's available.
  - A public load balancer.
  - An Oracle Autonomous Database Serverless instance.

    - The instance should have 2 ECPUs and 20GB storage and 20GB backup storage.
  
- At least one free OCI auth token (note that the maximum is two per user).

- On a local machine, you need:

  - The Kubernetes command-line interface (kubectl). [Installing kubectl documentation](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
  - Oracle Cloud Infrastructure command-line interface (CLI). [Quickstart - Installing the CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm#Quickstart).
  - Oracle Backend for Microservices and AI command-line interface (oractl). [Download oractl](https://github.com/oracle/microservices-backend/releases/tag/OBAAS-1.4.0).
  - [OPTIONAL]Oracle Backend for Microservices and AI VS Code Extension. [Download VS Code Extension](https://github.com/oracle/microservices-backend/releases/tag/OBAAS-1.4.0).
  - [OPTIONAL]Oracle Backend for Microservices and AI IntelliJ plugin. [Download VS Code Extension](https://github.com/oracle/microservices-backend/releases/tag/OBAAS-1.4.0).

You can use the [cost estimator for pricing](https://www.oracle.com/cloud/costestimator.html).

## OCI policies

The following policies needs to be in place to be able to install Oracle Backend for Microservices and AI. Top level and their dependencies listed.

### Oracle Container Engine for Kubernetes

```text
Allow group `<group-name>` to manage cluster-family in `<location>`
├── Allow group `<group-name>` to inspect compartments in `<location>`
├── Allow group `<group-name>` to read virtual-network-family in `<location>`
├── Allow group `<group-name>` to use network-security-groups in `<location>`
├── Allow group `<group-name>` to use private-ips in `<location>`
├── Allow group `<group-name>` to use subnets in `<location>`
├── Allow group `<group-name>` to use vnics in `<location>`
├── Allow group `<group-name>` to manage cluster-node-pools in `<location>`
├── Allow group `<group-name>` to manage instance-family in `<location>`
└── Allow group `<group-name>` to manage public-ips in `<location>`
```

### VCN

```text
Allow group `<group-name>` to manage vcns in `<location>`
├── Allow group `<group-name>` to manage route-tables in `<location>`
├── Allow group `<group-name>` to manage-security-lists in `<location>`
├── Allow group `<group-name>` to manage-dhcp-options in `<location>`


Allow group `<group-name>` to manage vcns in `<location>`
Allow group `<group-name>` to manage route-tables in `<location>`
Allow group `<group-name>` to manage security-lists in `<location>`
Allow group `<group-name>` to manage dhcp-options in `<location>`
Allow group `<group-name>` to manage nat-gateways in `<location>`
Allow group `<group-name>` to manage service-gateways in `<location>`
Allow group `<group-name>` to manage network-security-groups in `<location>`
Allow group `<group-name>` to manage subnets in `<location>`
```

### Container Registry

```text
Allow group `<group-name>` to manage repos in `<location>`
```

### Object Storage

```text
Allow group `<group-name>` to read objectstorage-namespaces in `<location>`
Allow group `<group-name>` to manage objects in `<location>`
└── Allow group `<group-name>` to manage buckets in `<location>`
```

### Autonomous Database

```text
Allow group `<group-name>` to manage autonomous-database-family in `<location>`
```

### Vault

If you deploy Oracle Backend for Microservices and AI **STANDARD** edition you need the following policies.

```text
Allow group `<group-name>` to manage vaults in `<location>`
Allow group `<group-name>` to manage keys in `<location>`
```

#### Additional Vault

To allow Container Engine for Kubernetes to access Vault via Groups:

```text
Allow group `<group-name>` to manage policies in `<location>`
Allow group `<group-name>` to manage tag-namespaces in `<location>`
Allow group `<group-name>` to manage dynamic-groups in `<location>`
Allow group `<group-name>` to manage secret-family in `<location>`
```

### Oracle Resource Manager

```text
Allow group `<group-name>` to read orm-template in `<location>`
Allow group `<group-name>` to use orm-stacks in `<location>`
└── Allow group `<group-name>` to manage orm-jobs in `<location>`
Allow group `<group-name>` to manage orm-private-endpoints in `<location>`
```

## Summary of Components

Oracle Backend for Microservices and AI setup installs the following components.

| Component                    | Version       | Description                                                                                 |
|------------------------------|---------------|---------------------------------------------------------------------------------------------|
| Apache APISIX                | 3.9.1         | Provides full lifecycle API management.                                                     |
| Apache Kafka                 | 3.8.0 | Provides distributed event streaming.                                                       |
| cert-manager                 | 1.12.3        | Automates the management of certificates.                                                   |
| Coherence Operator           | 3.3.5        | Provides in-memory data grid.                                                               |
| Conductor Server             | 3.13.8        | Provides a Microservice orchestration platform.                                             |
| Kube State Metrics | 2.10.1 | Collects metrics for the Kubernetes cluster     |
| Metrics server | 0.7.0  | Source of container resource metrics for Kubernetes built-in autoscaling pipeline |
| NGINX Ingress Controller     | 1.10.1         | Provides traffic management solution for cloud‑native applications in Kubernetes.           |
| OpenTelemetry Collector      | 0.107.0        | Collects process and export telemetry data.                                                 |
| Oracle Database Observability Exporter | 1.3.1 | Exposes Oracle Database metrics in standard Prometheus format.                            |
| Oracle Database Operator     | 1.1.0          | Helps reduce the time and complexity of deploying and managing Oracle databases.            |
| Oracle Transaction Manager for Microservices | 24.2.1 | Manages distributed transactions to ensure consistency across Microservices.       |
| SigNoz                     | 0.75.0     | Observability stack and Dashboards for logs, metrics and tracing.                       |
| Spring Authorization Server  | 3.3.3  | Provides authentication and authorization for applications. |
| Spring Boot Admin server     | 3.3.3         | Manages and monitors Spring Cloud applications.                                             |
| Spring Cloud Config server   | 4.1.3      | Provides server-side support for an externalized configuration.                             |
| Spring Eureka service registry | 4.1.3 | Provides service discovery capabilities.                                          |
| Strimzi-Apache Kafka operator  | 0.43.0      | Manages Apache Kafka clusters.                                                              |

## Overview of the Setup Process

This video provides a quick overview of the setup process.

{{< youtube rAi10TiUraE >}}

Installing Oracle Backend for Microservices and AI and Microservice takes approximately one hour to complete. The following steps are involved:

- [Setup the OCI environment](#set-up-the-oci-environment)
- [Setup of the Local Environment](#set-up-the-local-machine)
- [Access environment variables from the OCI Console](#access-information-and-passwords-from-the-oci-console)

## Set Up the OCI Environment

To set up the OCI environment, process these steps:

1. Go to the [OCI Marketplace listing for Oracle Backend for Microservices and AI](https://cloud.oracle.com/marketplace/application/138899911).

    <!-- spellchecker-disable -->
    {{< img name="ebaas-mp-listing" size="large" lazy=false >}}
    <!-- spellchecker-enable -->

    Choose the target compartment, agree to the terms, and click **Launch Stack**.  This starts the wizard and creates the new stack. On the first page, choose a compartment to host your stack and select **Next** and Configure the variables for the infrastructure resources that this stack will create when you run the apply job for this execution plan.

    <!-- spellchecker-disable -->
    {{< img name="ebaas-stack-page1" size="large" lazy=false >}}
    <!-- spellchecker-enable -->

1. In the **Backend as A Service** Section, fill in the following configuration variables as needed and select **Next**:

    - `Compartment` : Select the compartment where you want to install Oracle Backend for Microservices and AI.
    - `Application Name` (optional) : A random pet name that will be used as the application name if left empty.
    - `Edition` : Select between *COMMUNITY* and *STANDARD* Edition.
        - *COMMUNITY* - for developers for quick start to testing Spring Boot Microservices with an integrated backend. Teams can start with the deployment and scale up as processing demand grows. Community support only.
        - *STANDARD* - focused for pre-prod and production environments with an emphasis on deployment, scaling, and high availability. Oracle support is included with a Oracle Database support agreement. All features for developers are the same so start here if you’re porting an existing Spring Boot application stack and expect to get into production soon.  This edition allows for additional Bring Your Own (BYO) capabilities.
    - `Existing Authorization Token` (optional) - Enter an existing Authorization token. The token is used by the cluster to pull images from the Oracle Container Registry. If left empty the token will be created.

      **WARNING:** Deletion or expiration of the token will result in the failure to pull images later.  Also you must have one free OCI auth token (note that the maximum is two per user). You can *NOT* use someone elses token.

    | Edition   | BYO Network  | BYO Database     | Production Vault | Registry Scanning |
    |-----------|--------------|------------------|------------------| ------------------|
    | Community |              |                  |                  |                   |
    | Standard  | x            | x                | x                | x                 |

    <!-- spellchecker-disable -->
    {{< img name="oci-stack-app-name" size="large" lazy=false >}}
    <!-- spellchecker-enable -->

1. If you check the checkbox *Set Administrator Passwords* in the **Administrator Passwords** section you have the option to fill in the following passwords (if not they are autogenerated):

   - `APISIX Administrator Password` (optional) : Leave blank to auto-generate.
   - `SigNoz Administrator Password` (optional) : Leave blank to auto-generate.
   - `ORACTL Administrator Password` optional) : Leave blank to auto-generate. This is the password for the `obaas-admin` user.
   - `ORACTL User Password` (optional) : Leave blank to auto-generate. This is the password for the `obaas-user` user.
   
      <!-- spellchecker-disable -->
      {{< img name="oci-stack-passwords" size="large" lazy=false >}}
      <!-- spellchecker-enable -->

1. (*Standard Edition Only*) If you check the checkbox *Bring Your Own Virtual Cloud Network* in the **Network Options** section you can use an existing Virtual Cloud Network.  This is required to Bring Your Own Database (*Standard Edition Only*).

      <!-- spellchecker-disable -->
      {{< img name="oci-stack-network-options" size="large" lazy=false >}}
      <!-- spellchecker-enable -->

    > For more information on the network requirements and topology of the Oracle Backend for Microservices and AI including the options for *Bring Your Own Virtual Cloud Network*, please see the [Networking](../infrastructure/networking) documentation.

1. In the **Kubernetes Cluster Options** section, fill in the following for the OKE Cluster Options:

   - `Public API Endpoint?` : This option allows access to the OKE Control Plane API Endpoint from the internet (public IP). If not selected, access can only be from a private virtual cloud network (VCN).
   - `API Endpoint Access Control` : Enter the CIDR block you want to give access to the Control Plane API. Default (and not recommended) is `0.0.0.0/0`.
   - `Node Pool Workers` : The number of Kubernetes worker nodes (virtual machines) attached to the OKE cluster.
   - `Node Pool Worker Shape` : The shape of the node pool workers.
   - `Node Workers OCPU` : The initial number of Oracle Compute Units (OCPUs) for the node pool workers.

   If you check the box `Deploy GPU Node Pool` a node pool with GPU will be created with the size of `GPU Node Pool Workers` (default 1) and the shape `Node Pool Worker Shape` (default VM.GPU.A10.1). **NOTE:** Make sure that the tenancy you are deploying to has resources to do so.

   > **NOTE:** Oracle recommends that you set `API Endpoint Access Control` to be as restrictive as possible

     <!-- spellchecker-disable -->
     {{< img name="oci-stack-oke-options" size="large" lazy=false >}}
     <!-- spellchecker-enable -->

1. In the **Load Balancers Options** section, fill in the following for the Load Balancers options:

   - `Enable Public Load Balancer` : This option allows access to the load balancer from the internet (public IP). If not
      selected, access can only be from a private VCN.
   - `Public Load Balancer Access Control` : Enter the CIDR block you want to give access to the Load Balancer. Default (and not recommended) is `0.0.0.0/0`.
   - `Public Load Balancer Ports Exposed` : The ports exposed from the load balancer.
   - `Minimum bandwidth` : The minimum bandwidth that the load balancer can achieve.
   - `Maximum bandwidth` : The maximum bandwidth that the load balancer can achieve.

   > **NOTE:** Oracle recommends that you set `Public Load Balancer Access Control` to be as restrictive as possible.

      <!-- spellchecker-disable -->
      {{< img name="oci-stack-lb-options" size="large" lazy=false >}}
      <!-- spellchecker-enable -->

1. In the **Database Options** section, you can modify the following Database options.

   - `Autonomous Database Compute Model` : Choose either ECPU (default) or OCPU compute model for the ADB.
   - `Autonomous Database Network Access` : Choose the Autonomous Database network access. Choose between *SECURE_ACCESS* and *PRIVATE_ENDPOINT_ACCESS*. **NOTE:** This option currently cannot be changed later.
      - *SECURE_ACCESS* - Accessible from outside the Kubernetes Cluster.  Requires mTLS and can be restricted by IP or CIDR addresses.
      - *PRIVATE_ENDPOINT_ACCESS* - Accessible only from inside the Kubernetes Cluster or via a Bastion service.  Requires mTLS.
   - `ADB Access Control` : Comma separated list of CIDR blocks from which the ADB can be accessed. This only applies if *SECURE_ACCESS* was chosen. Default (and not recommended) is `0.0.0.0/0`.
   - `Autonomous Database CPU Core Count` : Choose how many CPU cores will be elastically allocated.
   - `Allow Autonomous Database CPU Auto Scaling` : Enable auto scaling for the ADB CPU core count (x3 ADB CPU).
   - `Autonomous Database Data Storage Size` : Choose ADB Database Data Storage Size in gigabytes (ECPU) or terabytes (OCPU).
   - `Allow Autonomous Database Storage Auto Scaling` : Allow the ADB storage to automatically scale.
   - `Autonomous Database License Model` : The Autonomous Database license model.
   - `Create an Object Storage Bucket for ADB` : Create a Object Storage bucket, with the appropriate access policies, for the ADB.

    > **NOTE:** Oracle recommends that you restrict by IP or CIDR addresses to be as restrictive as possible.

      <!-- spellchecker-disable -->
      {{< img name="oci-stack-db-options" size="large" lazy=false >}}
      <!-- spellchecker-enable -->

1. (*Standard Edition Only*) If *Bring Your Own Virtual Cloud Network* has been selected in the **Network Options** section, then you have the option to *Bring Your Own Database* in the section **Database Options**.

      <!-- spellchecker-disable -->
      {{< img name="oci-stack-byodb-options" size="large" lazy=false >}}
      <!-- spellchecker-enable -->

    > For more information on the *Bring Your Own Database* option for the Oracle Backend for Microservices and AI including the required values, please review the [Database](../infrastructure/database) documentation.

1. (*Standard Edition Only*) If you check the checkbox *Enable Container Registry Vulnerability Scanning* in the section **Additional Options** you will enable the automatic Vulnerability Scanning on images stored in the Oracle Container Registry.

      <!-- spellchecker-disable -->
      {{< img name="oci-stack-additional-options" size="large" lazy=false >}}
      <!-- spellchecker-enable -->

1. Now you can review the stack configuration and save the changes. Oracle recommends that you do not check the **Run apply** option. This gives you the opportunity to run the "plan" first and check for issues. Click **Create**

   <!-- spellchecker-disable -->
   {{< img name="oci-private-template-create-stack-config-review" size="large" lazy=false >}}
   <!-- spellchecker-enable -->

1. Apply the stack.

   After you create the stack, you can test the plan, edit the stack, and apply or destroy the stack.

   Oracle recommends that you test the plan before applying the stack in order to identify any issues before you start
   creating resources. Testing a plan does not create any actual resources. It is just an exercise to tell you what would
   happen if you did apply the stack.

   You can test the plan by clicking on **Plan** and reviewing the output. You can fix any issues (for example, you may find that you do not have enough quota for some resources) before proceeding.

   <!-- spellchecker-disable -->
   {{< img name="oci-stack-plan" size="large" lazy=false >}}
   <!-- spellchecker-enable -->

1. When you are happy with the results of the test, you can apply the stack by clicking on **Apply**. This creates your Oracle Backend as a Service and Microservices for a Spring Cloud environment. This takes about 20 minutes to complete. Much of this time is spent provisioning the Kubernetes cluster, worker nodes, database and all the included services. You can watch the logs to follow the progress of the operation.

    <!-- spellchecker-disable -->
    {{< img name="oci-stack-apply" size="large" lazy=false >}}
    <!-- spellchecker-enable -->

1. The OCI Resource Manager applies your stack and generates the execution logs. The apply job takes approximately 45 minutes.

    <!-- spellchecker-disable -->
    {{< img name="oci-stack-apply-logs" size="large" lazy=false >}}
    <!-- spellchecker-enable -->

1. When the **Apply** job finishes you can collect the OKE access information by clicking on **Outputs**.

    <!-- spellchecker-disable -->
    {{< img name="oci-stack-outputs" size="large" lazy=false >}}
    <!-- spellchecker-enable -->

1. Click on **Copy** for the variable named `kubeconfig_cmd`. Save this information because it is needed to access the OKE cluster.

    <!-- spellchecker-disable -->
    {{< img name="oci-stack-output-oke" size="large" lazy=false >}}
    <!-- spellchecker-enable -->

## Set Up the Local Machine

To set up the local machine, process these steps:

1. Set up cluster access.

   To access a cluster, use the `kubectl` command-line interface that is installed (see the [Kubernetes access](../cluster-access)) locally.
   If you have not already done so, do the following:

1. Install the `kubectl` command-line interface (see the [kubectl documentation](https://kubernetes.io/docs/tasks/tools/install-kubectl/)).

1. Generate an API signing key pair. If you already have an API signing key pair, go to the next step. If not:

   a. Use OpenSSL commands to generate the key pair in the required P-Early-Media (PEM) format. If you are using Windows, you need to install Git Bash for Windows in order to run the commands. See [How to Generate an API Signing Key](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#two).

   b. Copy the contents of the public key to the clipboard to paste the value into the Console later.

1. Add the public key value of the API signing key pair to the **User Settings** for your user name. For example:

   a. In the upper right corner of the OCI Console, open the **Profile** menu (User menu symbol) and click **User Settings** to view the details.

   b. Click **Add Public Key**.

   c. Paste the value of the public key into the window and click **Add**.

      The key is uploaded and its fingerprint is displayed (for example, d1:b2:32:53:d3:5f:cf:68:2d:6f:8b:5f:77:8f:07:13).

1. Install and configure the Oracle Cloud Infrastructure CLI. For example:

   a. Install the Oracle Cloud Infrastructure CLI version 2.6.4 (or later). See [Quickstart](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm#Quickstart).

   b. Configure the Oracle Cloud Infrastructure CLI. See [Configuring the CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliconfigure.htm#Configuring_the_CLI).

1. Install the Oracle Backend for Microservices and AI command-line.

   The Oracle Backend for Microservices and AI command-line interface, `oractl`, is available for Linux and Mac systems. Download the binary that you want from the [Releases](https://github.com/oracle/microservices-backend/releases/tag/OBAAS-1.4.0) page and add it to your PATH environment variable. You can rename the binary to remove the suffix.

   If your environment is a Linux or Mac machine, run `chmod +x` on the downloaded binary. Also, if your environment is a Mac, run the following command. Otherwise, you get a security warning and the CLI does not work:

   `sudo xattr -r -d com.apple.quarantine <downloaded-file>`

## Access information and passwords from the OCI Console

You can get the necessary access information from the OCI COnsole:

- OKE Cluster Access information e.g. how to generate the kubeconfig information.
- Oracle Backend for Microservices and AI Passwords.

The assigned passwords (either auto generated or provided by the installer) can be viewed in the OCI Console (ORM homepage). Click on Application Information in the OCI ORM Stack.

<!-- spellchecker-disable -->
{{< img name="azn-stack-app-info" size="large" lazy=false >}}
<!-- spellchecker-enable -->

You will presented with a screen with the access information and passwords. **NOTE**: The passwords can also be accessed from the k8s secrets.

<!-- spellchecker-disable -->
{{< img name="oci-stack-app-info" size="large" lazy=false >}}
<!-- spellchecker-enable -->
