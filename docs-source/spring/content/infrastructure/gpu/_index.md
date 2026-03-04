---
title: "GPUs for AI"
description: "GPUs for AI workload"
keywords: "gpu ollama llm spring springboot microservices oracle"
---

Oracle Backend for Microservices and AI provides an option during installation to provision a set of Kubernetes nodes with NVIDIA A10 GPUs that are suitable for running AI workloads.  If you choose that option during installation, you may also specify how many nodes are provisioned.  The GPU nodes will be in a separate Node Pool to the normal CPU nodes, which allows you to scale it independently of the CPU nodes. They are also labeled so that you can target appropriate workloads to them using node selectors and/or affinity rules.

To view a list of nodes in your cluster with a GPU, you can use this command:

```bash
$ kubectl get nodes -l 'node.kubernetes.io/instance-type=VM.GPU.A10.1'
NAME           STATUS   ROLES   AGE     VERSION
10.22.33.45    Ready    node    2m44s   v1.30.1
```

## Running a Large Language Model on your GPU nodes

One very common use for GPU nodes is to run a self-hosted Large Language Model (LLM) such as `llama3` for inferencing or `nomic-embed-text` for embedding.

Companies often want to self-host an LLM to avoid sending private or sensitive data outside of their organization to a third-party provider, or to have more control over the costs of running the LLM and associated infrastructure.

One excellent way to self-host LLMs is to use [Ollama](https://ollama.com/).

To install Ollama on your GPU nodes, you can use the following commands:

1. Add the Ollama helm repository:

    ```bash
    helm repo add ollama-helm https://otwld.github.io/ollama-helm/
    ```

1. Update your helm repositories:

    ```bash
    helm repo update
    ```

1. Create a `values.yaml` file to configure how Ollama should be installed, including which node(s) to run it on.  Here is an example that will run Ollama on a GPU node and will pull the `llama3` model.

    ```yaml
    ollama:
      gpu:
        enabled: true
        type: 'nvidia'
        number: 1
      models:
        - llama3
    nodeSelector:
      node.kubernetes.io/instance-type: VM.GPU.A10.1
    ```

  For more information on how to configure Ollama using the helm chart, refer to [its documentation](https://artifacthub.io/packages/helm/ollama-helm/ollama).

1. Create a namespace to deploy Ollama in:

    ```bash
    kubectl create ns ollama
    ```

1. Deploy Ollama using the helm chart:

    ```bash
    helm install ollama ollama-helm/ollama --namespace ollama  --values ollama-values.yaml
    ```

### Interacting with Ollama

You can interact with Ollama using the provided command line tool, called `ollama`. For example, to list the available models, use the `ollama ls` command:

```bash
kubectl -n ollama exec svc/ollama -- ollama ls
NAME            ID              SIZE    MODIFIED
llama3:latest   365c0bd3c000    4.7 GB  2 minutes ago
```

To ask the LLM a question, you can use the `ollama run` command:

```bash
$ kubectl -n ollama exec svc/ollama -- ollama run llama3 "what is spring boot?"
Spring Boot is an open-source Java-based framework that simplifies the development of web applications and microservices. It's a subset of the larger Spring ecosystem, which provides a comprehensive platform for building enterprise-level applications.

...
```

### Using LLMs hosted by Ollama in your Spring application

Our self-paced hands-on example **CloudBank AI** includes an example of how to [build a simple chatbot](https://oracle.github.io/microservices-backend/cloudbank/springai/simple-chat) using Spring AI and Ollama.
