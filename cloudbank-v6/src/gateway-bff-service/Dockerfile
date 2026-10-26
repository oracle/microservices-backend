# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.
FROM maven:3.9.16-eclipse-temurin-25 AS builder
WORKDIR /workspace
COPY pom.xml ./
COPY src/gateway-bff-service/pom.xml src/gateway-bff-service/pom.xml
COPY src/gateway-bff-service/src/main src/gateway-bff-service/src/main
RUN mvn -B -ntp -f src/gateway-bff-service/pom.xml -Dmaven.test.skip=true package \
    && cp src/gateway-bff-service/target/gateway-bff-service-*.jar /tmp/gateway-bff-service.jar

FROM container-registry.oracle.com/java/jdk-no-fee-term:25-oraclelinux9
WORKDIR /app
ENV HOME=/tmp
USER 10001:10001
COPY --from=builder --chown=10001:10001 /tmp/gateway-bff-service.jar /app/app.jar
EXPOSE 8089
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
