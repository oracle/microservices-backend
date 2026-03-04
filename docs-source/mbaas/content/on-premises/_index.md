---
Title: "On-Premises Installation"
---

# On-Premises Installation

The Oracle Backend for Parse Platform is available to install On-Premises.  The On-Premises installation includes both a _Desktop_ installation and
an _Estate_ installation.

The _Desktop_ installation can be used to explore a non-Production environment, while the _Estate_ installation is targeted for a Production infrastructure.

## Prerequisites

You must meet the following prerequisites to use the Oracle Backend for Parse Platform On-Premises. You need access to:

* An Oracle Database Enterprise Edition 19.3.0.0
* A Container Repository
* A Kubernetes cluster
* [Python 3+](https://www.python.org/)

When installing on a _Desktop_, the previously mentioned prerequisites are met through an additional setup task, but there are additional desktop
system or software requirements. For example:

* 2 CPUs or more
* 8 GB of free memory
* 60 GB of free disk space (40 GB Minikube and container images, 20 GB database)
* Internet connection
* [Minikube](https://minikube.sigs.k8s.io/docs/start/)
* [Podman](https://podman.io/getting-started/)[^1]
* Oracle Single Sign-On (SSO) account to download the database image

## Download

Download [Oracle Backend for Parse Platform](https://github.com/oracle/microservices-backend/releases/download/OBAAS-1.0.0/on-prem-mbaas_v0.1.1.zip).

## Setup

An On-Premises installation, whether _Desktop_ or _Estate_, consists of defining the Parse application and infrastructure followed by running the
Configuration Management Playbook to build images and deploy the Microservices.

For an _Estate_ installation, you need a Kubernetes cluster and the `kubectl` command-line interface must be configured to communicate with the cluster.

A Helper Playbook is provided for _Desktop_ installations to assist in defining the infrastructure. Review the appropriate documentation for examples of
installing and defining the _Desktop_ installation.

* [macOS Ventura (x86)](macos_ventura/_index.md)
* [Oracle Linux 8 (x86)](ol8/_index.md)

The _Desktop_ Playbook is run as part of the Configuration Management Playbook.

## Download the Database/Oracle REST Data Services (ORDS) Images (_Desktop_  Installation)

The _Desktop_ installation provisions an Oracle Database into the Kubernetes cluster.  The images must be downloaded from the [Oracle Cloud Infrastructure Registry (Container Registry)](https://container-registry.oracle.com/) before continuing.

After installing Podman:

1. Log in to the Container Registry:

   `podman login container-registry.oracle.com`

2. Pull the database image:

   `podman pull container-registry.oracle.com/database/enterprise:19.3.0.0`

3. Pull the ORDS image:

   `podman pull container-registry.oracle.com/database/ords:21.4.2-gh`

### Defining the Parse Application (_Estate_  Installation)

The application is defined in `ansible/vars/mbaas.yaml`. For example:

```yaml
---
mbaas_edition: "COMMUNITY"
app_name: "MYAPP"
app_id: "PiITzsu3RCc499RRDOYOBgWnyAlMm6695r1536y1"
master_key: "Q5CP7MHpoZhSwbk39XpHxamp4rJJ4F3vPZ3NZ7ee"
dashboard_username: "ADMIN"
dashboard_password: "OZ0-mSt-27Evb-Qy"
storage: ""
access_key: "N/A"
private_key: "N/A"
...
```

You can use any arbitrary string as your `app_name`, `app_id`, and `master_key`. These are used by your clients to authenticate with the Parse Server.  It is recommended to specify a unique `dashboard_username` and `dashboard_password`.

### Defining the Database  (_Estate_  Installation)

The database is defined in `ansible/roles/database/vars/main.yaml`. For example:

```yaml
---
database_oracle_dbs: ["BAASPDB"]
database_default_db: BAASPDB
BAASPDB: # noqa: var-naming[pattern]
  username: "PDBADMIN"
  password: "Correct-horse-Battery-staple-35"
  service: "(DESCRIPTION=(ADDRESS=(PROTOCOL=tcp)(HOST=localhost)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=BAASPDB)))"
  ocid: ""
...
```

The `oracle_dbs` and `default_db` keys should be the name of your Pluggable Database (PDB).  These keys are followed by the PDB and keys defining how to
access the PDB. If using Mutual Transport Layer Security (mTLS) authentication, specify the full path of the wallet file.

### Defining the Container Repository  (_Estate_  Installation)

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

Specify the URL or authentication credentials for your Container Repository in `registry_pull_url`, `registry_push_url`, `registry_username`, and `registry_password`.

For the `registry_pull_auth` and `registry_push_auth` sections, manually log into your repository and copy the values found in created file, located in `$HOME/.config/containers/auth.json`

Why is there duplication between the push and pull URL's?  The push URL is used from the deployment machine while the pull URL is used inside the pods. If you
have a private registry inside the Kubernetes cluster, these URL's could be different. This is the case for the _Desktop_ installation. The push URL
is `localhost:5000`, while the pull URL is `<Registry Pod ClusterIP>:5000`.

## Configuration Management

From the source package, run the Configuration Management Playbook.

### Install Ansible

Using Python, install Ansible to run the Configuration Management Playbook. The Helper scripts create a Python virtual environment and installs Ansible and
any additional modules. For example:

```bash
./setup_ansible.sh
source ./activate.env
```

### Desktop Playbook

If this is an _Estate_ installation, the infrastructure should be manually defined as previously mentioned. If this is a _Desktop_ installation, run the
Helper Playbook to define the infrastructure. For example:

```bash
ansible-Playbook desktop-apply.yaml
```

### Build and Push Images to the Container Repository

For the _Desktop_ installation, start a new terminal and tunnel or port-forward to the Minikube cluster.  Refer to the specific platform details for more information.

For both installations, run the Images Playbook on the original terminal. For example:

```bash
ansible-playbook ansible/images_build.yaml
```

### Install the Microservices

To install Microservices, process this command:

```bash
ansible-Playbook ansible/k8s_apply.yaml -t full
```

Next, go to the [macOS Ventura (x86)](../on-premises/macos_ventura/) page to learn how to use the newly installed environment.

## Footnotes

[^1]: Certification has been performed against Podman. However, other container or virtual machine managers are available and may be substituted. Experience is
needed.
