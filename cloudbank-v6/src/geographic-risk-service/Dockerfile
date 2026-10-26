FROM --platform=linux/amd64 container-registry.oracle.com/java/jdk-no-fee-term:25-oraclelinux9
WORKDIR /app
COPY --chown=185:0 maven/target/geographic-risk-service.jar app.jar
COPY --chown=185:0 maven/target/libs libs
USER 185
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
