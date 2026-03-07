---
title: External Secrets Operator
sidebar_position: 7
---
## External Secrets Operator

:::important
The External Secrets Operator is an optional prerequisite for Oracle Backend for Microservices and AI
:::

External Secrets Operator is a Kubernetes operator that integrates external secret management systems like OCI Vault, AWS Secrets Manager,
HashiCorp Vault, Google Secrets Manager, Azure Key Vault and many more. The operator reads information from external APIs and automatically injects the values into a Kubernetes Secret.

Full [documentation](https://external-secrets.io/latest/)

![External Secrets Operator](images/diagrams-high-level-simple.png)

### Installing External Secrets Operator

External Secrets Operator will be installed if the `external-secrets.enabled` is set to `true` in the `values.yaml` file. The default namespace for External Secrets Operator is `external-secrets`.
