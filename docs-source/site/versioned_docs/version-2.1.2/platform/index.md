---
title: Platform Services Overview
sidebar_position: 0
---

Oracle Backend for Microservices and AI includes a set of pre-integrated platform services that handle common infrastructure concerns — API routing, service discovery, messaging, distributed transactions, secrets management, and more. These services are deployed and managed via Helm and can be enabled or disabled individually in your `values.yaml`.

## API Gateway & Networking

<table aria-label="API Gateway &amp; Networking table">
  <thead>
    <tr>
      <th scope="col">Service</th>
      <th scope="col">Description</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row"><a href="./apacheapisix">Apache APISIX</a></th>
      <td>Cloud-native API gateway for routing, traffic management, and rate limiting</td>
    </tr>
    <tr>
      <th scope="row"><a href="./eureka">Spring Boot Eureka Server</a></th>
      <td>Service registry for automatic discovery between microservices</td>
    </tr>
    <tr>
      <th scope="row"><a href="./envoygateway">Envoy Gateway</a></th>
      <td>CNCF graduated implementation of the Kubernetes Gateway API</td>
    </tr>
  </tbody>
</table>

## Messaging & Event Streaming

<table aria-label="Messaging &amp; Event Streaming table">
  <thead>
    <tr>
      <th scope="col">Service</th>
      <th scope="col">Description</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row"><a href="./strimzi_operator">Strimzi Kafka Operator</a></th>
      <td>Kubernetes operator for deploying and managing Apache Kafka clusters</td>
    </tr>
  </tbody>
</table>

## Data & Transactions

<table aria-label="Data &amp; Transactions table">
  <thead>
    <tr>
      <th scope="col">Service</th>
      <th scope="col">Description</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row"><a href="./otmm">Oracle Transaction Manager for Microservices</a></th>
      <td>Distributed transaction coordinator supporting XA, LRA, and TCC consistency models</td>
    </tr>
    <tr>
      <th scope="row"><a href="./dboperator">Oracle Database Operator</a></th>
      <td>Kubernetes operator for provisioning and managing Oracle Database instances</td>
    </tr>
    <tr>
      <th scope="row"><a href="./coherence">Coherence Operator</a></th>
      <td>In-memory data grid for caching, data distribution, and compute</td>
    </tr>
  </tbody>
</table>

## Operations & Security

<table aria-label="Operations &amp; Security table">
  <thead>
    <tr>
      <th scope="col">Service</th>
      <th scope="col">Description</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row"><a href="./dbexporter">Oracle Database Metrics Exporter</a></th>
      <td>Exposes Oracle Database metrics for monitoring and alerting</td>
    </tr>
    <tr>
      <th scope="row"><a href="./esooperator">External Secrets Operator</a></th>
      <td>Syncs secrets from external stores (OCI Vault, AWS, HashiCorp Vault) into Kubernetes</td>
    </tr>
    <tr>
      <th scope="row"><a href="./sbadminserver">Spring Boot Admin Server</a></th>
      <td>Web dashboard for monitoring and managing Spring Boot applications</td>
    </tr>
    <tr>
      <th scope="row"><a href="./conductor">MicroTx Workflow Orchestration</a></th>
      <td>Workflow orchestration engine for multi-step service choreography</td>
    </tr>
  </tbody>
</table>

## Architecture

![Architecture](../OBaaS-Architecture.png "Oracle Backend for Microservices and AI Architecture")
