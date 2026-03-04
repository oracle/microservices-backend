---
title: "Developer Installation - Oracle Linux 8 (x86)"
description: "Custom installation on Oracle Linux for Oracle Backend for Microservices and AI"
keywords: "installation ol oraclelinux nonproduction development onprem custom spring springboot microservices development oracle backend"
---

This is an description of installing on a Oracle Linux 8 desktop.

Read the [On-Premises](../../on-premises) documentation and ensure that your desktop meets the minimum system requirements.

## Setup

### Create a Non-Root User

Create a new user. While any user name can be created, the rest of this documentation refers to the non-root user as `obaas`:

As `root`, process the following:

```bash
useradd obaas
```

### Download Oracle Backend for Microservices and AI

Download the latest version of [Oracle Backend for Microservices and AI](https://github.com/oracle/microservices-backend/releases/download/OBAAS-1.4.0/onprem-ebaas_latest.zip) and unzip into a new directory.

As the `obaas` user, run this command:

```bash
unzip onprem-ebaas_latest.zip -d ~/obaas
```

### Setup SSH-Key Access for obaas user

Future access to the `obaas` user requires a direct login (not `sudo` or `su`).  To setup ssh-key access as `obaas`, run the following commands:

```bash
mkdir ~/.ssh
vi ~/.ssh/authorized_keys
```

Paste the public key of your client machines into the `~/.ssh/authorized_keys` file, and change the permissions as follows:

```bash
chmod 700 .ssh
chmod 600 .ssh/authorized_keys
```

### Update the operating system

Assuming the source was unzipped to `~obaas/obaas`, as the `root` user, update the operating system by running the `ol8_onprem.sh` script from the unzipped package:

```bash
~obaas/obaas/ol8_onprem.sh
```

This script performs the following actions:

* Install required operating system Packages
* Install Minikube
* Set Python3 as the default python
* Enable cgroup v2
* Enable IP Tables
* Update the container runtime configuration

### (Optional) OCI Host Filesystem

If this is being installed on an OCI Compute instance, grow the filesystem:

As `root`:

```bash
/usr/libexec/oci-growfs
```

### Reboot

**IMPORTANT** After the operating system has been updated, `reboot` the host.

## Install

The remaining steps require **direct login** as the `obaas` user without using `sudo` or `su`.

### Download the Database or Oracle REST Data Services (ORDS) Images

The non-production installation provisions an Oracle database into the Kubernetes cluster. The images must be downloaded from [Oracle Cloud Infrastructure Registry (Container Registry)](https://container-registry.oracle.com/) before continuing.

While directly logged into the `obaas` user, process these steps:

1. Log in to the Container Registry. For example:

   `podman login container-registry.oracle.com`

1. Pull the database image. For example:

   `podman pull container-registry.oracle.com/database/enterprise:19.3.0.0`

1. Pull the ORDS image. For example:

   `podman pull container-registry.oracle.com/database/ords:21.4.2-gh`

#### Troubleshooting

If the `podman pull` command fails, navigate in a web browser to [Oracle container registry](https://container-registry.oracle.com), click the "database" tile and select "enterprise".  On the right hand side of the page, if prompted, sign-in.  Select "Language" and accept the Terms.  Try the `podman pull` command again.

### Start MiniKube

While directly logged into the `obaas` user, run these commands:

```bash
minikube config set rootless true
minikube config set driver podman
minikube start --cpus max --memory 16G --disk-size='40g' --container-runtime=containerd
minikube addons enable ingress
echo "KUBECONFIG=~/.kube/config" >> ~/.bashrc
```

### Install Ansible

While directly logged into the `obaas` user, change to the source directory and install Ansible by running these commands:

```bash
cd ~/obaas
./setup_ansible.sh
source ./activate.env
```

### Define the Infrastructure

Use the Helper Playbook to define the infrastructure. This Playbook also:

* Creates additional namespaces for the Container Registry and database.
* Creates a private Container Registry in the Kubernetes cluster.
* Modifies the Microservices application to be desktop compatible.

Assuming the source was unzipped to `~/obaas`, run the following command as the `obaas` user:

`ansible-playbook ~/obaas/ansible/desktop_apply.yaml`

### Open a Tunnel

In order to push the images to the Container Registry in the Kubernetes cluster, open a new terminal and process this command while being directly logged into the `obaas` user:

```bash
cd ~/obaas
source ./activate.env
kubectl port-forward service/private -n container-registry 5000:5000  > /dev/null 2>&1 &
```

### Build the Images

Build and push the images to the Container Registry in the Kubernetes cluster.

Assuming the source was unzipped to `~/obaas`, run the following command as the `obaas` user:

```bash
cd ~/obaas
source ./activate.env
ansible-playbook ~/obaas/ansible/images_build.yaml
```

After the images are built and pushed, the port-forward is no longer required and can be stopped.

### Deploy Microservices

Assuming the source was unzipped to `~/obaas`, run this command as the `obaas` user:

```bash
cd ~/obaas
source ./activate.env
ansible-playbook ~/obaas/ansible/k8s_apply.yaml -t full
```

## Notes

### config-server and obaas-admin Pod Failures

The Pods in the `azn-server`, `config-server`, and `obaas-admin` namespaces rely on the database that is created in the `oracle-database-operator-system`. During the initial provisioning, these Pods start well before the database is available resulting in initial failures. They resolve themselves once the database becomes available.

You can check on the status of the database by running this command:

`kubectl get singleinstancedatabase baas -n oracle-database-operator-system -o "jsonpath={.status.status}"`

### VPN and Proxies

If you are behind a Virtual Private Network (VPN) or proxy, see [Minikube Proxies and VPNs](https://minikube.sigs.k8s.io/docs/handbook/vpn_and_proxy/) for more details on additional tasks.

Next, go to the [Getting Started](../getting-started/) page to learn more.
