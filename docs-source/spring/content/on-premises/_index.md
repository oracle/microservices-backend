---
title: "Custom Installations"
description: "Custom installations of Oracle Backend for Microservices and AI"
keywords: "installation onprem on-premises custom spring springboot microservices development oracle backend"
---

The Oracle Backend for Microservices and AI is available to install in your own "custom" environment, which may be an on-premises data center environment, a different cloud provider, or a developer's desktop.

## Prerequisites

You must meet the following prerequisites to use the Oracle Backend for Microservices and AI On-Premises. You need:

* Access to Oracle Database Enterprise Edition 19.3.0.0
* Access to a Container Repository
* Access to a Kubernetes cluster
* [Python 3+](https://www.python.org/)

When installing in a _desktop_ environment, for example a developer's desktop, the previously mentioned pre-requisites may be met through an additional setup task, but there are additional desktop system or software requirements. For example:

* 2 CPUs or more
* 8 GB of free memory
* 60 GB of free disk space (40 GB minikube and container images, 20 GB database)
* Internet connection
* [Minikube](https://minikube.sigs.k8s.io/docs/start/) or similar
* [Podman](https://podman.io/getting-started/)[^1] or similar
* Oracle Single Sign-On (SSO) account to download the database image

## Download

Download the latest release of [Oracle Backend for Microservices and AI](https://github.com/oracle/microservices-backend/releases/download/OBAAS-1.4.0/onprem-ebaas_latest.zip).

## Setup

A custom installation consists of defining the infrastructure followed by running the Configuration Management Playbook to build images and deploy the Microservices.

For a custom installation, you need to have a Kubernetes cluster and the `kubectl` command-line interface must be configured to communicate with your cluster.

A Helper Playbook has been provided for desktop installations to assist in defining a specific infrastructure consisting of podman and minikube as outlined in the example documentation:

* [macOS Ventura (x86)](../on-premises/macos_ventura/)
* [Oracle Linux 8 (x86)](../on-premises/ol8/)

If your infrastructure does not match that defined in the above examples, do not run the Helper Playbook.

## Download the Database or Oracle REST Data Services (ORDS) Images (Desktop Installation)

The desktop installation provisions an Oracle database to the Kubernetes cluster. The images must be downloaded
from [Oracle's Container Registry](https://container-registry.oracle.com/) before continuing.

After installing Podman, process these steps:

1. Log in to Oracle Cloud Infrastructure Registry (Container Registry). For example:

   `podman login container-registry.oracle.com`

2. Pull the database image. For example:

   `podman pull container-registry.oracle.com/database/enterprise:19.3.0.0`

3. Pull the ORDS image. For example:

   `podman pull container-registry.oracle.com/database/ords:21.4.2-gh`

### Defining the Application

The application is defined in `ansible/vars/ebaas.yaml`. For example:

```yaml
---
ebaas_edition: "COMMUNITY"
apisix_admin_password: "Correct-horse-Battery-staple-35"
signoz_admin_password: "Correct-horse-Battery-staple-35"
oractl_admin_password: "Correct-horse-Battery-staple-35"
oractl_user_password: "Correct-horse-Battery-staple-35"
...
```

Create the `ansible/vars/ebaas.yaml` file, setting values as required.  If this is a desktop installation, this file will be created for you by the Desktop Helper playbook.

### Defining the Database

The database is defined in `ansible/roles/database/vars/main.yaml`. For example:

```yaml
---
database_oracle_dbs: ["BAASPDB"]
database_default_db: BAASPDB
BAASPDB: # noqa: var-naming[pattern]
  username: "PDBADMIN"
  password: "Correct-horse-Battery-staple-35"
  type: "EXTERNAL"
  service: "(DESCRIPTION=(ADDRESS=(PROTOCOL=tcp)(HOST=localhost)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=BAASPDB)))"
  ocid: ""
...
```

Create the `ansible/roles/database/vars/main.yaml` file, setting values as required.  If this is a desktop installation, this file will be created for you by the Desktop Helper playbook.

The `database_oracle_dbs` and `database_default_db` key values should be the name of your Pluggable Database (PDB). These are followed by the PDB name and Key/Values defining how to access the PDB.

The `type` can be either:

* **EXTERNAL**: A Pre-existing Oracle Database.  Define `service` and leave `ocid` blank.
* **ADB-S**: A Pre-Existing Oracle Autonomous Serverless (ADB-S) database; provide the `ocid` for the ADB-S.  Leave `service` blank.
* **SIDB_CONTAINER**: This will create a 19c containerized database inside the Kubernetes Cluster as part of the deployment.  Leave `ocid` and `service` blank.

### Defining the Container Repository

The Container Repository is defined in `ansible/roles/registry/vars/main.yaml`. For example:

```yaml
---
registry_username: "oracle"
registry_password: "Correct-horse-Battery-staple-35"
registry_push_url: "docker.io/myorg"
registry_push_auth:
  auths:
    docker.io/myorg:
      auth: "b3JhY2xlOjdaUVgxLXhhbFR0NTJsS0VITlA0"
registry_pull_url: "docker.io/myorg"
registry_pull_auth:
  auths:
    docker.io/myorg:
      auth: "b3JhY2xlOjdaUVgxLXhhbFR0NTJsS0VITlA0"
...
```

Create the `ansible/roles/registry/vars/main.yaml` file, setting values as required.  If this is a desktop installation, this file will be created for you by the Desktop Helper playbook.

Specify the URL or authentication credentials for your Container Repository in `registry_pull_url`, `registry_push_url`, `registry_username`, and `registry_password`.

For the `registry_pull_auth` and `registry_push_auth` sections, manually log into your repository and copy the values found in the created file, located in `$HOME/.config/containers/auth.json`

There may be duplication between the push and pull URL's. The pull URL is used inside the Pods while the push URL is used from the
deployment machine. If you have a private registry inside the Kubernetes cluster, these URL's could be different. This is the case for
the _Desktop_ installation. For example, the push URL is `localhost:5000`, while the pull URL is `<Registry Pod ClusterIP>:5000`.

## Configuration Management Playbook

From the source package, run the Configuration Management Playbook.

### Install Ansible

Using Python, install Ansible to run the Configuration Management Playbook.  The Helper script creates a Python virtual environment
and installs Ansible along with other additional modules. For example:

```bash
./setup_ansible.sh
source ./activate.env
```

### Desktop Helper Playbook

If this is a desktop installation, then a Helper Playbook can be used to help define the infrastructure.  **Note** that this playbook should only be run if following the desktop installation examples:

* [macOS Ventura (x86)](../on-premises/macos_ventura/)
* [Oracle Linux 8 (x86)](../on-premises/ol8/)

Run the Desktop Helper Playbook to define the infrastructure. For example:

```bash
ansible-playbook ansible/desktop-apply.yaml
```

### Copy kubeconfig

For the desktop installation, this step will have been performed by the Desktop Helper playbook.

Copy the kubeconfig file to `ansible/roles/kubernetes/files`

### Build and Push Images to the Container Repository

For the desktop installation, start a new terminal and tunnel or port-forward to the Minikube cluster.  Refer to the specific platform details for more information.

For both installations, run the Images Playbook on the original terminal. For example:

```bash
ansible-playbook ansible/images_build.yaml
```

### Install the Microservices

Install the Microservices by running this command:

```bash
ansible-playbook ansible/k8s_apply.yaml -t full
```

## Footnotes

[^1]: Certification has been performed against Podman. However, other container or virtual machine managers are available and may be
substituted.
