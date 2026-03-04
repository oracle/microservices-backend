---
title: "Oracle Backend for Microservices and AI"
description: "Helidon, Spring and Spring Boot"
keywords: "spring springboot microservices development oracle backend helidon"
---

Oracle Backend for Microservices and AI allows developers to build microservices in Helidon and/or Spring Boot and provisions a "backend as a service" with Oracle Database and other infrastructure components that operate on multiple clouds. Oracle Backend for Microservices and AI vastly simplifies the task of building, testing, and operating microservices platforms for reliable, secure, and scalable enterprise applications.

{{< hint type=[warning] icon=gdoc_fire title="Version 1.4.0 (production) released July 2025" >}}
 Oracle Backend for Microservices and AI Version 1.4.0 is now generally available and suitable for production use. This version supports and recommends Helidon 4.2.x, Spring Boot 3,4.x, 3.3.x, 3.2.x, Spring 6.1 and Spring Cloud 2023.0.x, with limited backwards compatibility for Spring Boot 2.7.x.  
{{< /hint >}}

If you are building Spring Boot applications with Oracle Database, you should also check out [Spring Cloud Oracle](https://github.com/oracle/spring-cloud-oracle) which is the home of a number of the components used in Oracle Backend for Microservices and AI, and which you can also use in your own applications!

## Try it out with CloudBank AI

To learn more about deploying and using Oracle Backend for Microservices and AI, we recommend our
[CloudBank AI](https://bit.ly/cloudbankAI) self-paced, on-demand hands-on lab.

![CloudBank AI](./cloudbank-hol.png)

In the [CloudBank AI](https://bit.ly/cloudbankAI) hands-on lab, you can learn how to:

- Install Oracle Backend for Microservices and AI.
- Set up a development environment for Helidon and/or Spring Boot.
- Build Spring Boot microservices from scratch using Spring Web to create
  Representational State Transfer (REST) services.
- Use service discovery and client-side load balancing.
- Use Spring Actuator to allow monitoring of services.
- Create services that use asynchronous messaging with Java Message Service (JMS) instead of REST.
- Implement the Saga pattern to manage data consistency across microservices.
- Use the APISIX API Gateway to expose services to clients.
- Build a conversational chatbot using Spring AI and self-host LLMs with Ollama.

## Learn more

To learn more, watch this short introductory video:

{{< youtube 3MQy89oo894 >}}

In addition to an Oracle Autonomous Database Serverless instance, the following software components are deployed in an Oracle Cloud
Infrastructure (OCI) Container Engine for Kubernetes cluster (OKE cluster):

- [Oracle AI Explorer for Apps](platform/aiexpforapps/)
- [Apache APISIX API Gateway and Dashboard](platform/apigw/)
- [Apache Kafka](https://kafka.apache.org/)
- [SigNoz](observability/signoz/)
- [Apache Kafka](https://kafka.apache.org)
- [Netflix Conductor](platform/conductor/)
- [OpenTelemetry Collector](observability/tracing/)
- [Oracle Autonomous Database Serverless](database/)
- [Oracle Backend for Microservices and AI Command Line Interface (CLI)](development/cli/)
- [Oracle Backend for Microservices and AI Visual Studio Code Plugin](platform/vscode-plugin/)
- [Oracle Coherence](https://docs.oracle.com/en/middleware/standalone/coherence/)
- [Oracle Database Operator for Kubernetes (OraOperator or the operator)](https://github.com/oracle/oracle-database-operator)
- [Oracle Database Observability Exporter](https://github.com/oracle/oracle-db-appdev-monitoring)
- [Oracle Transaction Manager for Microservices (MicroTx)](platform/microtx/)
- [Spring Boot Admin dashboard](platform/spring-admin/)
- [Spring Cloud Config server](platform/config/)
- [Spring Cloud Eureka service registry](platform/eureka/)
- [ServiceOps Center](platform/soc/)
- Strimzi Kafka Operator

Developers also have access to development or build time services and libraries including:

- [Command-line interface (CLI)](development/cli/) to manage service deployment and configuration, including database schema management.
- [IntelliJ plugin](platform/intellij-plugin/) to manage service deployment and configuration.
- [OpenTelemetry Collector (including automatic instrumentation)](observability/tracing/).
- [Spring CLI](https://spring.io/projects/spring-cli) support for project creation.
- [Spring Cloud Config client](platform/config/).
- [Spring Eureka service discovery client](platform/eureka/).
- [Spring Cloud OpenFeign](https://spring.io/projects/spring-cloud-openfeign).
- [Spring Starters for Oracle Universal Connection Pool (UCP), Oracle Wallet, Oracle Advanced Queuing (AQ), and Transactional Event Queues (TxEventQ)](starters/).
- [Visual Studio Code (VS Code) plugin](platform/vscode-plugin/) to manage service deployment and configuration.

## Need help?

We'd love to hear from you!  You can contact us in the following channels:

- [#oracle-db-microservices Slack channel](https://oracledevs.slack.com/archives/C06L9CDGR6Z) in the Oracle Developers slack workspace.
- [Open an issue in GitHub](https://github.com/oracle/microservices-backend/issues/new).
