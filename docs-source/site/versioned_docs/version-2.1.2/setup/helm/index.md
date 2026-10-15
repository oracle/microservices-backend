---
title: Helm Installation Overview
sidebar_position: 0
---

## Installing OBaaS with Helm Charts

This guide outlines the steps to deploy Oracle Backend for Microservices and AI (OBaaS) to an existing Kubernetes cluster using Helm charts.

### Installation Steps

<table aria-label="OBaaS Helm installation steps">
  <thead>
    <tr>
      <th scope="col">Step</th>
      <th scope="col">Description</th>
      <th scope="col">Details</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row">1</th>
      <td><strong>Verify prerequisites</strong></td>
      <td>Confirm your Kubernetes cluster, database, and tooling meet the requirements.</td>
    </tr>
    <tr>
      <th scope="row">2</th>
      <td><strong>Install prerequisites chart</strong></td>
      <td>Install the cluster-scoped operators and CRDs (once per cluster).</td>
    </tr>
    <tr>
      <th scope="row">3</th>
      <td><strong>Install OBaaS chart</strong></td>
      <td>Install the OBaaS application chart into one or more namespaces.</td>
    </tr>
    <tr>
      <th scope="row">4</th>
      <td><strong>Verify installation</strong></td>
      <td>Confirm all pods are running and services are accessible.</td>
    </tr>
  </tbody>
</table>

### Detailed Guides

- [Prerequisites](./prereqs.md) — Kubernetes cluster, database, and tooling requirements
- [Helm Chart Installation](./install.md) — Full installation, architecture, and example configurations
- [Dependent Helm Chart References](./chart-references.md) — Version-pinned upstream README and values references for bundled dependency charts
