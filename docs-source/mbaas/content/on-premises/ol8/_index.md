---
Title: "Oracle Linux 8 (x86)"
---

# On-Premises Installation - Oracle Linux 8 (x86)

This is a description of installing On-Premises on an Oracle Linux 8 desktop.

Read [On-Premises](../index.md) and ensure that your desktop meets the minimum system requirements.

## Install

### Additional Operating System Packages

As the `root` user, install the following operating system packages:

```bash
dnf -y module install container-tools:ol8
dnf -y install conntrack podman curl
dnf -y install oracle-database-preinstall-21c
dnf -y install langpacks-en
dnf module install -y python39
dnf -y update
```

Set the default Python3 to Python 3.9:

```bash
alternatives --set python3 /usr/bin/python3.9
```

### Install MiniKube

As the `root` user, install minikube:

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
install minikube-linux-amd64 /usr/local/bin/minikube
```

### Create a Non-Root User

Create a new user. While any user name can be created, the rest of the documentation refers to the non-root user as `obaas`.

As `root`, process these commands:

```bash
useradd obaas
echo "obaas ALL=(ALL) NOPASSWD: /bin/podman" >> /etc/sudoers
```

### Download the Database/Oracle REST Data Services (ORDS) Images

The _Desktop_ installation provisions an Oracle Database into the Kubernetes cluster. The images must be downloaded from [Oracle Cloud Infrastructure Registry (Container Registry)](https://container-registry.oracle.com/) before continuing.

As the `obaas` user, take these steps:

1. Log in to the Container Registry:

   `podman login container-registry.oracle.com`

2. Pull the database image:

   `podman pull container-registry.oracle.com/database/enterprise:19.3.0.0`

3. Pull the ORDS image:

   `podman pull container-registry.oracle.com/database/ords:21.4.2-gh`

### Start Minikube

As the `obaas` user, process these commands:

```bash
echo "PATH=\$PATH:/usr/sbin" >> ~/.bashrc
minikube config set driver podman
minikube start --cpus max --memory 7900mb --disk-size='40g' --container-runtime=cri-o
minikube addons enable ingress
```

### Download Oracle Backend for Parse Server

As the `obaas` user, download [Oracle Backend for Parse Server](https://github.com/oracle/microservices-backend/releases/download/OBAAS-1.0.0/onprem-mbaas_latest.zip) and unzip into a new directory. For example:

```bash
unzip onprem-mbaas_latest.zip -d ~/obaas
```

### Install Ansible

As the `obaas` user, change to the source directory and install Ansible:

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

Assuming the source was unzipped to `~/obaas`, as the `obaas` user, run this command:

`ansible-playbook ~/obaas/ansible/desktop_apply.yaml`

### Open a Tunnel

In order to push the images to the Container Registry in the Kubernetes cluster, open a new terminal and start a port-forward service.

As the `obaas` user, run these commands:

```bash
source ./activate.env
kubectl port-forward service/private -n container-registry 5000:5000 &`
```

### Build the Images

Build and push the images to the Container Registry in the Kubernetes cluster. Assuming the source was unzipped to `~/obaas`, as the `obaas` user, run this command:

`ansible-playbook ~/obaas/ansible/images_build.yaml`

After the images are built and pushed, the port-forward service is no longer required and can be stopped.

### Deploy Microservices

Assuming the source was unzipped to `~/obaas`, as the `obaas` user, run this command to deploy Microservices:

`ansible-playbook ~/obaas/ansible/k8s_apply.yaml -t full`

## Notes

### VPN and Proxies

If you are behind a Virtual Private Network (VPN) or proxy, click on the following URL for more details on additional tasks:

https://minikube.sigs.k8s.io/docs/handbook/vpn_and_proxy/

Next, go to the [Getting Started](../getting-started/) page to learn how to use the newly installed environment.