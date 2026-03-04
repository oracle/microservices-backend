# customer-helidon

Helidon MP version of the "customer" microservice built using the **Helidon MP profile** for enterprise Java applications with CDI, JPA, and microservices capabilities.

## Build and run

### Prerequisites
- JDK 21
- Maven 3.8+

### Building the Application

The build process creates a **thin JAR deployment package** as a ZIP file containing the application JAR and all dependencies:

```bash
mvn clean package
```

This creates:
- `target/customer-helidon.jar` - The thin application JAR
- `target/customer-helidon-deployment.zip` - Complete deployment package with structure:
  ```
  customer-helidon.jar          (main application)
  app/
    libs/                       (all dependency JARs)
  ```

### Building and Pushing Container Image

#### Environment Setup (macOS with Rancher Desktop)

```bash
# Set Docker host for JKube compatibility
export DOCKER_HOST=unix:///Users/$USER/.rd/docker.sock
```

#### Commands

```bash
# Build thin JAR and libs
mvn clean package

# Build container image
mvn k8s:build

# Push to Oracle Cloud Registry
docker push us-ashburn-1.ocir.io/tenancy/customer-helidon:5.0-SNAPSHOT
```

#### Output
- **JAR**: `target/customer-helidon.jar` (thin JAR)
- **Dependencies**: `target/libs/` (all dependencies)
- **Deployment**: `target/customer-helidon-deployment.zip`
- **Image**: Uses JKube Java base image with automatic Helidon configuration

### Running the Application

**Option 1: Using the thin JAR (requires dependencies in classpath):**
```bash
# Extract the deployment ZIP first
cd target
unzip customer-helidon-deployment.zip
java -jar customer-helidon.jar
```

**Option 2: Using Maven to run directly:**
```bash
mvn exec:java
```

## Quick Start with Local Oracle Database

To run against a local Oracle Docker container, simply:

1. **Start Oracle Database container:**
   ```bash
   docker run -d --name oracle-db -p 1521:1521 \
       -e ORACLE_PWD=Welcome12345 \
       container-registry.oracle.com/database/free:latest
   ```

2. **Uncomment database configuration** in `src/main/resources/application.yaml`:
   ```yaml
   javax.sql.DataSource.customer.URL = jdbc:oracle:thin:@//localhost:1521/freepdb1
   javax.sql.DataSource.customer.user = customer
   javax.sql.DataSource.customer.password = Welcome12345
   ```

3. **Rebuild and run:**
   ```bash
   mvn clean package
   cd target && unzip customer-helidon-deployment.zip
   java -jar customer-helidon.jar
   ```

The application will automatically create the necessary database tables on startup using Hibernate's DDL auto-generation.

### Basic:
```bash
curl -X GET http://localhost:8080/simple-greet
Hello World!
```

### JSON:
```bash
curl -X GET http://localhost:8080/greet
{"message":"Hello World!"}

curl -X GET http://localhost:8080/greet/Joe
{"message":"Hello Joe!"}

curl -X PUT -H "Content-Type: application/json" -d '{"greeting" : "Hola"}' http://localhost:8080/greet/greeting

curl -X GET http://localhost:8080/greet/Jose
{"message":"Hola Jose!"}
```

### Try health
```bash
curl -s -X GET http://localhost:8080/health
{"outcome":"UP",...
```

### Try metrics
```bash
# Prometheus Format
curl -s -X GET http://localhost:8080/metrics
# TYPE base:gc_g1_young_generation_count gauge
. . .

# JSON Format
curl -H 'Accept: application/json' -X GET http://localhost:8080/metrics
{"base":...
. . .
```

## Building a Native Image

The generation of native binaries requires an installation of GraalVM 22.1.0+.
You can build a native binary using Maven as follows:

```bash
mvn -Pnative-image install -DskipTests
```

The generation of the executable binary may take a few minutes to complete depending on your hardware and operating system. When completed, the executable file will be available under the `target` directory and be named after the artifact ID you have chosen during the project generation phase.

## Docker Support

### Building the Docker Image Locally

**Note:** The `Dockerfile.manual` must be renamed to `Dockerfile` before building locally, as JKube uses the Dockerfile when present.

```bash
# Rename Dockerfile for local build
git mv Dockerfile.manual Dockerfile

# Build the Docker image
docker build -t customer-helidon .

# Rename back to avoid conflicts with JKube builds
git mv Dockerfile Dockerfile.manual
```

### Running the Docker Image
```bash
docker run --rm -p 8080:8080 customer-helidon:latest
```

Exercise the application as described above.

## Configuration

### Application Properties (`application.yaml`)
```yaml
# Microprofile server properties
server.port=8080
server.host=0.0.0.0
# Change the following to true to enable the optional MicroProfile Metrics REST.request metrics
metrics.rest-request.enabled=false

# Application properties. This is the default greeting
app.greeting=Hello

# Database connection factory - specifies Oracle UCP driver for connection pooling
javax.sql.DataSource.customer.connectionFactoryClassName = oracle.jdbc.pool.OracleDataSource

# Local Oracle Database Configuration
# Uncomment the following lines to connect to a local Oracle Docker container out-of-the-box:
# javax.sql.DataSource.customer.URL = jdbc:oracle:thin:@//localhost:1521/freepdb1
# javax.sql.DataSource.customer.user = customer
# javax.sql.DataSource.customer.password = Welcome12345

# Hibernate/JPA Configuration
hibernate.hbm2ddl.auto=create
hibernate.show_sql=true
hibernate.format_sql=true
# Fix JTA transaction coordinator issue
hibernate.transaction.coordinator_class=jta

# Eureka service discovery configuration
server.features.eureka.client.base-uri=http://eureka.eureka:8761/eureka
server.features.eureka.instance.name=helidon-customer-service
server.features.eureka.instance.hostName=helidon.helidon

# OpenTelemetry configuration
otel.sdk.disabled=false
otel.service.name=customer-helidon
otel.logs.exporter=otlp
otel.exporter.otlp.endpoint=http://localhost:4318
otel.exporter.otlp.protocol=http/protobuf
```

## OpenTelemetry Logging

This service implements **Structured JSON Logging with Trace Correlation** to natively export logs to observability backends like SigNoz without manual OpenTelemetry SDK configurations.

### Architecture: "Platform Pays Once"

This application relies on the underlying Kubernetes OpenTelemetry DaemonSet to parse structured logs. The microservice itself is completely decoupled from telemetry exporters or APIs.

**Key Components:**
1. **Dependencies** (`pom.xml`):
   - `slf4j-api` and `logback-classic` (Replaces JUL)
   - `logstash-logback-encoder` (Formats output as JSON)
   - `opentelemetry-logback-mdc-1.0` (Bridges OTel context to MDC)

2. **Configuration** (`src/main/resources/logback.xml`):
   Standardizes all container application text output to pure JSON string lines via the `LogstashEncoder`.

3. **Trace Injection** (`src/main/java/com/example/MdcFilter.java`):
   A custom JAX-RS `ContainerRequestFilter` that intercepts incoming HTTP requests, extracts the active `trace_id` and `span_id` from the OpenTelemetry SpanContext, and securely drops them into the SLF4J ThreadLocal MDC. 

4. **Cluster Collection**:
   Because the logs are printed to `stdout` in pure JSON with trace IDs attached, the cluster's OpenTelemetry DaemonSet natively scrapes, parses, and correlates the logs entirely outside of the application's runtime.

### Benefits

- ✅ **No Manual SDK Setup** - No custom `GlobalOpenTelemetry` endpoints to configure inside the app.
- ✅ **Automatic Trace Correlation** - Any vanilla `LOGGER.info()` statement instantly gets stamped with the distributed Trace ID.
- ✅ **Zero Exporter Overhead** - The application only prints text locally; the cluster agent handles the expensive network gRPC telemetry export.
- ✅ **SigNoz Ready** - Log levels and trace graphs are perfectly mapped out-of-the-box.

## Build Architecture

This project uses:
- **Helidon MP (MicroProfile)** - Enterprise Java microservices profile
- **Thin JAR deployment** - Application JAR + separate dependencies for optimal Docker layering
- **Maven Assembly Plugin** - Creates deployment ZIP with proper structure for containerization
- **Hibernate + JTA** - Database persistence with transaction management
- **Oracle UCP** - Connection pooling for Oracle Database
- **Eureka integration** - Service discovery support

## Dockerfile Structure

The included Dockerfile uses a **multi-stage build**:

```dockerfile
# 1st stage, build the app
FROM container-registry.oracle.com/java/jdk-no-fee-term:21 as build

# Install maven
WORKDIR /usr/share
RUN set -x && \
    curl -O https://archive.apache.org/dist/maven/maven-3/3.8.4/binaries/apache-maven-3.8.4-bin.tar.gz && \
    tar -xvf apache-maven-*-bin.tar.gz && \
    rm apache-maven-*-bin.tar.gz && \
    mv apache-maven-* maven && \
    ln -s /usr/share/maven/bin/mvn /bin/

WORKDIR /helidon

# Create a first layer to cache the "Maven World" in the local repository.
ADD pom.xml .
RUN mvn package -Dmaven.test.skip -Declipselink.weave.skip -DskipOpenApiGenerate

# Do the Maven build with fat JAR!
ADD src src
RUN mvn package -DskipTests

# 2nd stage, build the runtime image
FROM container-registry.oracle.com/java/jdk-no-fee-term:21
WORKDIR /helidon

# Copy ONLY the fat JAR (not libs directory)
COPY --from=build /helidon/target/*.jar app.jar

# Simple fat JAR execution
CMD ["java", "-jar", "app.jar"]
EXPOSE 8080
```

## Deploying to OBaaS (Oracle Backend for Spring Boot)

This service is designed to be deployed as part of the CloudBank application in an OBaaS environment.

### 1. Prerequisites
- **OBaaS Installed**: Ensure the OBaaS platform is running in your Kubernetes cluster.
- **Database Secrets**: The service relies on existing secrets for database credentials (e.g., `obaas-tenant1-db-authn`, `obaas-tenant1-adb-tns-admin`).
- **Helm**: Ensure Helm is installed.

### 2. Configuration (`values.yaml`)
A `values.yaml` file is provided to configure the service. You **must** verify/update the following parameters before deployment:

| Parameter | Description | Value in `values.yaml` |
| :--- | :--- | :--- |
| `image.repository` | OCI Registry path for the image | e.g., `us-phoenix-1.ocir.io/mytenancy/customer-helidon` |
| `image.tag` | Image version tag | `5.0-SNAPSHOT` |
| `database.walletSecret` | Secret containing the Autonomous Database wallet | `<release>-adb-tns-admin` |
| `database.authN.secretName` | Secret containing DB credentials for the app | `<release>-db-authn` |
| `database.privAuthN.secretName` | Secret containing DB credentials for Liquibase | `adb-admin-creds` |
| `obaas.framework` | Framework type (Required for correct startup) | `HELIDON` |

> **Note:** The secrets `adb-admin-creds` and `<release>-db-authn` are typically created by the `3-k8s_db_secrets.sh` script during the installation process. Ensure these exist in your namespace before deployment.

### 3. Build and Push
Use the following command to build the container image and push it to your OCI registry:

```bash
export REGISTRY="<your-registry-region>.ocir.io/<your-tenancy>/<your-repo>"
mvn clean package k8s:build k8s:push -Dimage.registry=$REGISTRY -Dimage.tag=5.0-SNAPSHOT
```

### 4. Deploy using Helm
Deploy the service using the shared `obaas-sample-app` chart:

```bash
helm upgrade --install customer-helidon ../../helm/app-charts/obaas-sample-app \
  -f values.yaml \
  -n tenant1
```

### 5. Verification
After deployment, verify the service using the provided test script:

```bash
# 1. Port forward the service
kubectl port-forward svc/customer-helidon 8080:8080 -n tenant1

# 2. Run the test script (in a separate terminal)
./test-endpoints.sh
```

