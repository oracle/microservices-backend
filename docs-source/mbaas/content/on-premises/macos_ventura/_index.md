---
Title: "macOS Ventura (x86)"
---

# On-Premises Installation - macOS Ventura (x86)

This is description of installing On-Premises on a macOS Ventura desktop.

Read [On-Premises](../index.md) and ensure that your desktop meets the minimum system requirements.

## Install

### Podman

To install Podman, process these commands:

```bash
brew install podman
PODMAN_VERSION=$(podman -v |awk '{print $NF}')
sudo /usr/local/Cellar/podman/${PODMAN_VERSION}/bin/podman-mac-helper install
podman machine init --cpus 4 --disk-size 60 --memory 8192 --rootful --now
podman system connection default podman-machine-default-root
```

### Download the Database/Oracle REST Data Services (ORDS) Images

The _Desktop_ installation provisions an Oracle Database into the Kubernetes cluster. The images must be downloaded from [Oracle Cloud Infrastructure Registry (Container Registry)](https://container-registry.oracle.com/) before continuing.

1. Log in to the Container Registry:

   `podman login container-registry.oracle.com`
   
2. Pull the database image:

   `podman pull container-registry.oracle.com/database/enterprise:21.3.0.0`
   
3. Pull the ORDS Image:

   `podman pull container-registry.oracle.com/database/ords:21.4.2-gh`

### Minikube

To install Minikube, process these commands:

```bash
brew install minikube
minikube config set driver podman
minikube start --cpus 4 --memory max --container-runtime=containerd
minikube addons enable ingress
```

### Download Oracle Backend for Spring Boot and Microservices

Download the [Oracle Backend for Parse Server](https://github.com/oracle/microservices-backend/releases/download/OBAAS-1.0.0/onprem-mbaas_latest.zip) and unzip into a new directory.

### Install Ansible

To install Ansible, process these commands:

```bash
./setup_ansible.sh
source ./activate.env
```

### Define the Infrastructure

Use the Helper Playbook to define the infrastructure. This Playbook also:

* Creates additional namespaces for the Container Registry and database.
* Creates a private Container Registry in the Kubernetes cluster.
* Modifies the Microservices application to be desktop compatible.

Run this command:

`ansible-playbook ansible/desktop_apply.yaml`

### Open a Tunnel

In order to push the images to the Container Registry in the Kubernetes cluster, open a new terminal and start a tunnel.

Run this command:

`minikube tunnel`

To test access to the registry, run this command:

`curl -X GET -k https://localhost:5000/v2/_catalog`

This `curl` results in the following:

```text
{"errors":[{"code":"UNAUTHORIZED","message":"authentication required","detail":[{"Type":"registry","Class":"","Name":"catalog","Action":"*"}]}]}
```

### Build the Images

Build and push the images to the Container Registry in the Kubernetes cluster by running this command:

`ansible-playbook ansible/images_build.yaml`

After the images are built and pushed, the tunnel is no longer required and can be stopped.

### Deploy Oracle Backend for Spring Boot and Microservices

Deploy the database and Microservices by running this command:

`ansible-playbook ansible/k8s_apply.yaml -t full`

## Notes

### VPN and Proxies

If you are behind a Virtual Private Network (VPN) or proxy, click on the following URL for more details on additional tasks:

https://minikube.sigs.k8s.io/docs/handbook/vpn_and_proxy/

Next, go to the [Oracle Linux 8 (x86)](../on-premises/ol8/) page to learn how to use the newly installed environment.