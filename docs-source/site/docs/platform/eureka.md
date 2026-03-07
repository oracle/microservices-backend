---
title: Spring Boot Eureka Server
sidebar_position: 8
---
## Spring Boot Eureka Server

Oracle Backend for Microservices and AI includes the Spring Boot Eureka service registry, which stores information about client services. Typically, each microservice registers with Eureka at startup. Eureka maintains a list of all active service instances, including their IP addresses and ports. Other services can look up this information using a well-known key, enabling service-to-service communication without hardcoding addresses at development or deployment time.

:::note
 Want to use Eureka in your Helidon applications - see [below](#enable-a-helidon-application-for-eureka)
:::

### Installing Spring Boot Eureka Server

Spring Boot Eureka Server will be installed if the `eureka.enabled` is set to `true` in the `values.yaml` file. The default namespace for Spring Boot Eureka Server is `eureka`.

### Access Eureka Web User Interface

To access the Eureka Web User Interface, use kubectl port-forward to create a secure channel to `service/eureka`. Run the following command to establish the secure tunnel (replace the example namespace `obaas-dev` with the namespace where the Spring Boot Eureka Server is deployed):

```shell
kubectl port-forward -n obaas-dev svc/eureka 8761
```

Open the [Eureka web user interface](http://localhost:8761)

![Eureka Web User Interface](images/eureka-web.png)

### Enable a Spring Boot application for Eureka

To enable a Spring Boot application, you need to add the following dependency.

```xml
<dependency>
    <groupId>org.springframework.cloud</groupId>
    <artifactId>spring-cloud-starter-netflix-eureka-client</artifactId>
</dependency>
```

And to configure the application to register with Eureka, add the following to the `application.yaml` file. The variables in this configuration are automatically injected into your deployment and pods when you deploy applications to Oracle Backend for Microservices and AI using the OBaaS deployment Helm chart.

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

### Enable a Helidon application for Eureka

To enable a Helidon application, you need to add the following dependency.

```xml
<dependency>
    <groupId>io.helidon.integrations.eureka</groupId>
    <artifactId>helidon-integrations-eureka</artifactId>
    <scope>runtime</scope>
</dependency>
```

And to configure the application to register with Eureka, add the following to the `application.yaml` file:

```properties
server.features.eureka.enabled=true
server.features.eureka.instance.name=${eureka.instance.hostname}
server.features.eureka.client.base-uri=${eureka.client.service-url.defaultZone}
server.features.eureka.client.register-with-eureka=true
server.features.eureka.client.fetch-registry=true
server.features.eureka.instance.preferIpAddress=true
```


### Enable a Helidon application for Eureka

To enable a Helidon application, you need to add the following dependency to your `pom.xml`:

```xml
<dependency>
    <groupId>io.helidon.integrations.eureka</groupId>
    <artifactId>helidon-integrations-eureka</artifactId>
</dependency>
```

Then, update your application configuration in `src/main/resources/application.yaml`:

```yaml
server:
  features:
    eureka:
      enabled: true
      client:
        base-uri: ${eureka.client.service-url.defaultZone}
        connect-timeout: PT10S
        read-timeout: PT30S
      instance:
        name: "your-service-name"  # IMPORTANT: Use 'name' not 'app-name'
        hostname: ${eureka.instance.hostname}
        prefer-ip-address: ${eureka.instance.preferIpAddress:true}
```

Notes:

* Use `instance.name` (not `app-name`)
* Use ISO 8601 duration format: `PT10S` (not `10s`)
* Environment variables will be injected by OBaaS

If you deploy your application using the OBaaS application Helm chart, you can enable Eureka by
setting `obaas.eureka.enabled: true` in your `values.yaml`.

:::note
 Helidon does not support the Eureka URL being a list.  If you have multiple Eureka server replicas (which is normal),
 you wil need to edit the deployment template to only include one server address.
:::

Update your `templates/deployment.yaml` to ensure the Helidon framework section uses a single Eureka URL:

```
{{- if eq .Values.obaas.framework "HELIDON" }}
{{- if $.Values.obaas.eureka.enabled }}
  - name: eureka.client.service-url.defaultZone
    value: "http://eureka-0.eureka.{{ .Values.obaas.namespace }}.svc.cluster.local:8761/eureka"
  - name: eureka.instance.hostname
    value: {{ include "obaas-app.fullname" . }}-{{ $.Release.Namespace }}
  - name: eureka.instance.preferIpAddress
    value: "true"
{{- end }}
{{- end }}
```