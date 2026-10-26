# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

FROM maven:3.9.16-eclipse-temurin-25 AS builder

WORKDIR /workspace

COPY pom.xml ./
COPY src/azn-server/pom.xml src/azn-server/pom.xml
COPY src/loan-application-service/pom.xml src/loan-application-service/pom.xml
COPY src/document-ingest/pom.xml src/document-ingest/pom.xml
COPY src/document-review-service/pom.xml src/document-review-service/pom.xml
COPY src/decision-service/pom.xml src/decision-service/pom.xml
COPY src/ai-agent-service/pom.xml src/ai-agent-service/pom.xml
COPY src/geographic-risk-service/pom.xml src/geographic-risk-service/pom.xml
COPY src/policy-embedding-support/pom.xml src/policy-embedding-support/pom.xml
COPY src/policy-retrieval-service/pom.xml src/policy-retrieval-service/pom.xml
COPY src/policy-loader/pom.xml src/policy-loader/pom.xml
COPY src/workflow-token-refresh-worker/pom.xml src/workflow-token-refresh-worker/pom.xml
COPY src/gateway-bff-service/pom.xml src/gateway-bff-service/pom.xml

# Cache dependencies independently from application sources.
RUN mvn -B -ntp -DskipTests dependency:go-offline

COPY src/azn-server/src/main src/azn-server/src/main
COPY src/loan-application-service/src/main src/loan-application-service/src/main
COPY src/document-ingest/src/main src/document-ingest/src/main
COPY src/document-review-service/src/main src/document-review-service/src/main
COPY src/decision-service/src/main src/decision-service/src/main
COPY src/ai-agent-service/src/main src/ai-agent-service/src/main
COPY src/geographic-risk-service/src/main src/geographic-risk-service/src/main
COPY src/policy-embedding-support/src/main src/policy-embedding-support/src/main
COPY src/policy-retrieval-service/src/main src/policy-retrieval-service/src/main
COPY src/policy-loader/src/main src/policy-loader/src/main
COPY src/workflow-token-refresh-worker/src/main src/workflow-token-refresh-worker/src/main
COPY src/gateway-bff-service/src/main src/gateway-bff-service/src/main
COPY src/geographic-risk-service/src/assembly src/geographic-risk-service/src/assembly

RUN mvn -B -ntp -Dmaven.test.skip=true package \
    && cp src/azn-server/target/azn-server-*.jar /tmp/azn-server.jar \
    && cp src/loan-application-service/target/loan-application-service-*.jar /tmp/loan-application-service.jar \
    && cp src/document-ingest/target/document-ingest-*.jar /tmp/document-ingest.jar \
    && cp src/document-review-service/target/document-review-service-*.jar /tmp/document-review-service.jar \
    && cp src/decision-service/target/decision-service-*.jar /tmp/decision-service.jar \
    && cp src/ai-agent-service/target/ai-agent-service-*.jar /tmp/ai-agent-service.jar \
    && cp src/policy-retrieval-service/target/policy-retrieval-service-*.jar /tmp/policy-retrieval-service.jar \
    && cp src/policy-loader/target/policy-loader-*.jar /tmp/policy-loader.jar \
    && cp src/workflow-token-refresh-worker/target/workflow-token-refresh-worker-*.jar /tmp/workflow-token-refresh-worker.jar \
    && cp src/geographic-risk-service/target/geographic-risk-service.jar /tmp/geographic-risk-service.jar \
    && cp -R src/geographic-risk-service/target/libs /tmp/geographic-risk-libs

# One-shot database bootstrap used by the OBaaS/OKE deployment. This packages
# the same SQLcl/Liquibase flow used by Compose, but runs it directly against
# the target Autonomous Database through the OBaaS wallet and Secret mounts.
FROM container-registry.oracle.com/database/sqlcl:26.2.1 AS cloudbank-schema-init

USER root
WORKDIR /workspace
COPY --chown=10001:10001 src/loan-application-service/setup-local-db.sh /workspace/src/loan-application-service/setup-local-db.sh
COPY --chown=10001:10001 src/schema /workspace/src/schema

ENV HOME=/tmp
USER 10001:10001
ENTRYPOINT ["/bin/bash", "/workspace/src/loan-application-service/setup-local-db.sh"]

FROM container-registry.oracle.com/java/jdk-no-fee-term:25-oraclelinux9 AS runtime

WORKDIR /app
ENV HOME=/tmp
USER 10001:10001

ENTRYPOINT ["java", "-jar", "/app/app.jar"]

FROM runtime AS azn-server
COPY --from=builder --chown=10001:10001 /tmp/azn-server.jar /app/app.jar
EXPOSE 8080

FROM runtime AS loan-application-service
COPY --from=builder --chown=10001:10001 /tmp/loan-application-service.jar /app/app.jar
EXPOSE 8081

FROM runtime AS document-ingest
COPY --from=builder --chown=10001:10001 /tmp/document-ingest.jar /app/app.jar
EXPOSE 8082

FROM runtime AS document-review-service
COPY --from=builder --chown=10001:10001 /tmp/document-review-service.jar /app/app.jar
EXPOSE 8084

FROM runtime AS decision-service
COPY --from=builder --chown=10001:10001 /tmp/decision-service.jar /app/app.jar
EXPOSE 8088

FROM runtime AS ai-agent-service
COPY --from=builder --chown=10001:10001 /tmp/ai-agent-service.jar /app/app.jar
EXPOSE 8085

FROM runtime AS policy-retrieval-service
COPY --from=builder --chown=10001:10001 /tmp/policy-retrieval-service.jar /app/app.jar
EXPOSE 8086

FROM runtime AS policy-loader
COPY --from=builder --chown=10001:10001 /tmp/policy-loader.jar /app/app.jar
COPY --chown=10001:10001 synthetic_data/policy /app/policy

FROM runtime AS workflow-token-refresh-worker
COPY --from=builder --chown=10001:10001 /tmp/workflow-token-refresh-worker.jar /app/app.jar
EXPOSE 8087

FROM runtime AS geographic-risk-service
COPY --from=builder --chown=10001:10001 /tmp/geographic-risk-service.jar /app/app.jar
COPY --from=builder --chown=10001:10001 /tmp/geographic-risk-libs /app/libs
EXPOSE 8080
