---
title: Helm Installation Overview
sidebar_position: 0
---

## Installing OBaaS with Helm Charts

This guide outlines the steps to deploy Oracle Backend for Microservices and AI (OBaaS) to an existing Kubernetes cluster using Helm charts.

### Installation Steps

| Step | Description | Details |
|------|-------------|---------|
| 1 | **Verify prerequisites** | Confirm your Kubernetes cluster, database, and tooling meet the requirements. |
| 2 | **Install prerequisites chart** | Install the cluster-scoped operators and CRDs (once per cluster). |
| 3 | **Install OBaaS chart** | Install the OBaaS application chart into one or more namespaces. |
| 4 | **Verify installation** | Confirm all pods are running and services are accessible. |

### Detailed Guides

- [Prerequisites](./prereqs.md) — Kubernetes cluster, database, and tooling requirements
- [Helm Chart Installation](./install.md) — Full installation, architecture, and example configurations
