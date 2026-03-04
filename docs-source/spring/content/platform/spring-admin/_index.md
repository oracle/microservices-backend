---
title: "Spring Boot Admin"
description: "Using Spring Boot Admin to manage applications in Oracle Backend for Microservices and AI"
keywords: "admin springboot spring development microservices development oracle backend"
resources:
  - name: obaas-springadmin-apps
    src: "obaas-springadmin-apps.png"
    title: "Spring Admin DashboardI"
  - name: obaas-springadmin-svc-details
    src: "obaas-springadmin-svc-details.png"
    title: "Spring Admin Service Details"
  - name: obaas-eureka-dashboard
    src: "obaas-eureka-dashboard.png"
    title: "Eureka Dashboard"
---

## View Application Details Using the Spring Boot Admin Dashboard

Spring Boot Admin is a web application used for managing and monitoring Spring Boot applications. Applications are discovered from the
service registry. Most of the information displayed in the web user interface comes from the Spring Boot Actuator endpoints exposed by
the applications:

1. Expose the Spring Boot Admin dashboard using this command:

    ```shell
    kubectl -n admin-server port-forward svc/admin-server 8989
    ```

1. Open the Spring Boot Admin dashboard URL: <http://localhost:8989>

    <!-- spellchecker-disable -->
    {{< img name="obaas-springadmin-apps" size="medium" lazy=false >}}
    <!-- spellchecker-enable -->

    On the dashboard you will see all the internal services registered with Eureka. If you have deployed the sample application [CloudBank](https://github.com/oracle/microservices-backend/tree/main/cloudbank-v4) or done the [LiveLab for Oracle Backend for Microservices and AI](https://bit.ly/cloudbankAI) you will see those services.

    If you click (expand) an application and click on the instance of service you will details about the service instance, metrics, configuration, and so on,

    <!-- spellchecker-disable -->
    {{< img name="obaas-springadmin-svc-details" size="medium" lazy=false >}}
    <!-- spellchecker-enable -->
