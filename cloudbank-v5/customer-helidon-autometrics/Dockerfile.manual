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

