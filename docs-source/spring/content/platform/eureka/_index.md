---
title: "Eureka Service Discovery"
description: "Service discovery with Spring Eureka Service Registry in Oracle Backend for Microservices and AI"
keywords: "service discovery registry eureka springboot spring development microservices oracle backend"
resources:
  - name: obaas-eureka-dashboard
    src: "obaas-eureka-dashboard.png"
    title: "Eureka web user interface"
---

Oracle Backend for Microservices and AI includes the Spring Boot Eureka service registry, which is an application that stores information about client services or applications. Typically, each Microservice registers with the Eureka server at startup and the Eureka server maintains a list of all active instances of the service, including their ports and IP addresses. This information can be accessed by other services using a well-known key. This allows services to interact with each other without needing to know the other addresses at development or deployment time.

## Access the Eureka Web User Interface

To access the Eureka web user interface, process these steps:

1. Expose the Eureka web user interface using this command:

    ```shell
    kubectl port-forward -n eureka svc/eureka 8761
    ```

1. Open the Eureka web user interface URL <http://localhost:8761>

    <!-- spellchecker-disable -->
    {{< img name="obaas-eureka-dashboard" size="medium" lazy=false >}}
    <!-- spellchecker-enable -->

    On the dashboard you will see all the internal services registered with Eureka. If you have deployed the sample application [CloudBank](https://github.com/oracle/microservices-backend/tree/main/cloudbank-v4) or done the [LiveLab for Oracle Backend for Microservices and AI](https://bit.ly/cloudbankAI) you will see those services.

## Enable a Spring boot application for Eureka

To Spring boot application you need to add the following dependency

```xml
<dependency>
    <groupId>org.springframework.cloud</groupId>
    <artifactId>spring-cloud-starter-netflix-eureka-client</artifactId>
</dependency>
```

And to configure the application to register with Eureka add the following to the `application.yaml` file:

```yaml
eureka:
  instance:
    hostname: ${spring.application.name}
    preferIpAddress: true
  client:
    service-url:
      defaultZone: ${eureka.service-url}
    fetch-registry: true
    register-with-eureka: true
    enabled: true
```

## Enable a Helidon application for Eureka

To Spring boot application you need to add the following dependency

```xml
<dependency>
    <groupId>io.helidon.integrations.eureka</groupId>
    <artifactId>helidon-integrations-eureka</artifactId>
    <scope>runtime</scope>
</dependency>
```

And to configure the application to register with Eureka add the following to the `aaplication.yaml` file:

```properties
server.features.eureka.enabled=true
server.features.eureka.instance.name=${eureka.instance.hostname}
server.features.eureka.client.base-uri=${eureka.client.service-url.defaultZone}
server.features.eureka.client.register-with-eureka=true
server.features.eureka.client.fetch-registry=true
server.features.eureka.instance.preferIpAddress=true
```
