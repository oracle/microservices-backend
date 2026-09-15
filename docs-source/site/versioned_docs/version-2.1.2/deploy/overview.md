---
title: Deployment Overview
sidebar_position: 0
---

## Deploying Applications to Oracle Backend for Microservices and AI

This guide outlines the steps to build, deploy, and expose an application on Oracle Backend for Microservices and AI (OBaaS).

### Deployment Steps

<table aria-label="Deployment Steps table">
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
      <td><strong>Create container repositories</strong></td>
      <td>Set up a repository per microservice in your container registry (OCIR, ECR, ACR, etc.).</td>
    </tr>
    <tr>
      <th scope="row">2</th>
      <td><strong>Build and push images</strong></td>
      <td>Use Maven and Eclipse JKube to build JARs, create container images, and push to the registry.</td>
    </tr>
    <tr>
      <th scope="row">3</th>
      <td><strong>Create database secrets</strong></td>
      <td>Create Kubernetes secrets with privileged and per-service database credentials.</td>
    </tr>
    <tr>
      <th scope="row">4</th>
      <td><strong>Deploy with Helm</strong></td>
      <td>Install each service using the <code>obaas-sample-app</code> Helm chart with a per-service <code>values.yaml</code>.</td>
    </tr>
    <tr>
      <th scope="row">5</th>
      <td><strong>Create API gateway routes</strong></td>
      <td>Configure Apache APISIX routes to expose services externally via Eureka discovery.</td>
    </tr>
  </tbody>
</table>

### Detailed Guide

- [Deploying an Application to OBaaS](./deploy.md) — Full step-by-step walkthrough with commands and configuration examples
