---
title: Spring Cloud Config Server
sidebar_position: 11
---

OBaaS includes the Spring Cloud Config Server.  It is configured with the JDBC backend so that you can store your
configuration properties in your Oracle database.  The OBaaS database will be pre-configured during OBaaS installation
with a table to hold your properties.

Please refer to the [Spring Cloud Config Server documentation](https://docs.spring.io/spring-cloud-config/docs/current/reference/html/#_spring_cloud_config_server)
for more information about the server itself.

Here is the definition of the `PROPERTIES` table for your reference:

```
Name           Null?       Type
______________ ___________ _________________
ID             NOT NULL    NUMBER
APPLICATION                VARCHAR2(4000)
PROFILE                    VARCHAR2(4000)
LABEL                      VARCHAR2(4000)
PROP_KEY       NOT NULL    VARCHAR2(4000)
VALUE          NOT NULL    VARCHAR2(4000)
CREATED_ON                 TIMESTAMP(6)
CREATED_BY                 VARCHAR2(100)
UPDATED_ON                 TIMESTAMP(6)
UPDATED_BY                 VARCHAR2(100)
```

## Managing configuration properties in the database

If you have direct access to the database, you can log in and create, update, delete configuration properties in this table as needed.

If you do not have direct access to the database, you can run the necessary SQL statements in a pod in your Kubernetes cluster with the necessary credentials.

An example job definition is provided in [https://github.com/oracle/microservices-backend/blob/main/helm/app-charts/obaas-sample-app/examples/sqlcl-pod.yaml](https://github.com/oracle/microservices-backend/blob/main/helm/app-charts/obaas-sample-app/examples/sqlcl-pod.yaml)

You can edit the SQL statements in this manifest to suit your needs.  In the example file, you see the statements to list the currently defined
configuration properties, and then to add two new properties for an application called `billing` in its `default` profile and `latest` label.
See the [Spring Cloud Config Server documentation](https://docs.spring.io/spring-cloud-config/docs/current/reference/html/#_spring_cloud_config_server)
to understand how application, profile, and label are used.

```sql
-- list current config properties
select * from properties;
-- create some new config properties
insert into properties (application, profile, label, prop_key, value) values
('billing', 'default', 'latest', 'apikey', 'abc123'),
('billing', 'default', 'latest', 'subscription', 'xyz456');
```

Once you have edited the manifest, you can start a pod with a command like this:

```bash
kubectl apply -f your-sqlcl-pod.yaml -n obaas
```

Check the pod output to confirm it was successful, using a command like this:

```bash
kubectl -n obaas logs sqlcl

SQLcl: Release 25.4 Production on Mon Mar 23 16:51:50 2026

Copyright (c) 1982, 2026, Oracle.  All rights reserved.

Connected to:
Oracle AI Database 26ai Free Release 23.26.1.0.0 - Develop, Learn, and Run for Free
Version 23.26.1.0.0


   ID APPLICATION    PROFILE    LABEL     PROP_KEY        VALUE     CREATED_ON                         CREATED_BY    UPDATED_ON    UPDATED_BY
_____ ______________ __________ _________ _______________ _________ __________________________________ _____________ _____________ _____________
    1 billing        default    latest    apikey          abc123    23-MAR-26 04.49.53.000000000 PM    OBAAS_USER
    2 billing        default    latest    subscription    xyz456    23-MAR-26 04.49.53.000000000 PM    OBAAS_USER

Disconnected from Oracle AI Database 26ai Free Release 23.26.1.0.0 - Develop, Learn, and Run for Free
Version 23.26.1.0.0
```

Remember to remove your pod when you are finished, using a command like this:

```bash
kubectl -n obaas delete pod sqlcl
```

## Using Spring Cloud Config Server in your applications

When you deploy your application into your OBaaS environment using the OBaaS Application Helm Chart, make sure
you include the Spring Cloud Config Client in your application dependencies,
and set `configServer.enabled: true` if you want the Spring Cloud Config Server configuration to be injected
into your application:

```yaml
configServer:
  enabled: true
```

This will inject `spring.cloud.config.uri` into your application with the correct address for the Spring Cloud Config Server,
and will therefore allow you to refer to and use configuration properties in your application.


Please refer to the [Spring Cloud Config Client documentation](https://docs.spring.io/spring-cloud-config/docs/current/reference/html/#_spring_cloud_config_client)
for detailed information about how to use Spring Cloud Config in your applications, in particular to learn how application name,
profile and labels are used to lookup configuration properties.