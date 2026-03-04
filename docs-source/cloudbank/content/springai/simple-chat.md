+++
archetype = "page"
title = "A simple ChatBot"
weight = 1
+++

In this module, you will learn how to build a simple chatbot using Spring AI and Ollama.  

> **Note:** The example below can also be run on a regular CPU if you are using an environment where a GPU is not available, it will just be slower.

Oracle Backend for Microservices and AI provides an option during installation to provision a set of Kubernetes nodes with NVIDIA A10 GPUs that are suitable for running AI workloads. If you choose that option during installation, you may also specify how many nodes are provisioned. The GPU nodes will be in a separate Node Pool to the normal CPU nodes, which allows you to scale it independently of the CPU nodes. They are also labeled so that you can target appropriate workloads to them using node selectors and/or affinity rules.

To view a list of nodes in your cluster with a GPU, you can use this command: 

```bash
$ kubectl get nodes -l 'node.kubernetes.io/instance-type=VM.GPU.A10.1'
NAME           STATUS   ROLES   AGE     VERSION
10.22.33.45    Ready    node    2m44s   v1.30.1
```

### Running a Large Language Model on your GPU nodes

One very common use for GPU nodes is to run a self-hosted Large Language Model (LLM) such as `llama3` for inferencing or `nomic-embed-text` for embedding.

Companies often want to self-host an LLM to avoid sending private or sensitive data  outside their organization to a third-party provider, or to have more control over the costs of running the LLM and associated infrastructure.

One excellent way to self-host LLMs is to use [Ollama](https://ollama.com/).

To install Ollama on your GPU nodes, you can use the following commands:

1. Add the Ollama helm repository:

    ```bash
    helm repo add ollama-helm https://otwld.github.io/ollama-helm/
    ```

1. Update your helm repositories:

    ```bash
    helm repo update
    ```

1. Create a `ollama-values.yaml` file to configure how Ollama should be installed, including
   which node(s) to run it on.  Here is an example that will run Ollama on a GPU node
   and will pull the `llama3` model.

    ```yaml
    ollama:
      gpu:
        enabled: true
        type: 'nvidia'
        number: 1
      models:
        - llama3
    nodeSelector:
      node.kubernetes.io/instance-type: VM.GPU.A10.1
    ```

   For more information on how to configure Ollama using the helm chart, refer to
   [its documentation](https://artifacthub.io/packages/helm/ollama-helm/ollama).

   > **Note:** If you are using an environment where no GPU is available, you can run this on a CPU by changing the `values.yaml` file to the following:

   ```yaml
   ollama:
     gpu:
       enabled: false
     models:
       - llama3
   ``` 

1. Create a namespace to deploy Ollama in:

    ```bash
    kubectl create ns ollama
    ```

1. Deploy Ollama using the helm chart:

    ```bash
    helm install ollama ollama-helm/ollama --namespace ollama  --values ollama-values.yaml
    ```
1. You can verify the deployment with the following command:

   ```bash
   kubectl get pods -n ollama -w
   ```
   
   When the pod has the status `Running` the deployment is completed.

   ```text
   NAME                      READY   STATUS    RESTARTS   AGE
   ollama-659c88c6b8-kmdb9   0/1     Running   0          84s
   ```
   
### Test your Ollama deployment

You can interact with Ollama using the provided command line tool, called `ollama`.
For example, to list the available models, use the `ollama ls` command:

```bash
kubectl -n ollama exec svc/ollama -- ollama ls
NAME            ID              SIZE    MODIFIED
llama3:latest   365c0bd3c000    4.7 GB  2 minutes ago
```

To ask the LLM a question, you can use the `ollama run` command:

```bash
$ kubectl -n ollama exec svc/ollama -- ollama run llama3 "what is spring boot?"
Spring Boot is an open-source Java-based framework that simplifies the development
of web applications and microservices. It's a subset of the larger Spring ecosystem,
which provides a comprehensive platform for building enterprise-level applications.

...
```

### Using LLMs hosted by Ollama in your Spring application

A Kubernetes service named 'ollama' with port 11434 will be created so that your
applications can talk to models hosted by Ollama.

Now, you will create a simple Spring AI application that uses Llama3 to
create a simple chatbot.

> **Note:** The sample code used in this module is available [here](https://github.com/oracle/microservices-backend/tree/main/cloudbank-v4/chatbot).

1. Create a new Spring Boot project

   In a new directory called `chatbot`, create a file called `pom.xml` with the following content:

   ```xml
    <?xml version="1.0" encoding="UTF-8"?>
    <project xmlns="http://maven.apache.org/POM/4.0.0"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
        <modelVersion>4.0.0</modelVersion>

        <parent>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-parent</artifactId>
            <version>3.3.4</version>
            <relativePath/> <!-- lookup parent from repository -->
        </parent>
        
        <groupId>com.example</groupId>
        <artifactId>chatbot</artifactId>
        <version>0.0.1-SNAPSHOT</version>
        <name>chatbot</name>
        <description>A Simple ChatBot Application</description>

        <dependencies>
            <dependency>
                <groupId>org.springframework.ai</groupId>
                <artifactId>spring-ai-ollama-spring-boot-starter</artifactId>
            </dependency>
            <dependency>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-starter-web</artifactId>
                <version>3.3.4</version>
            </dependency>
        </dependencies>

        <repositories>
            <repository>
                <id>spring-milestones</id>
                <name>Spring Milestones</name>
                <url>https://repo.spring.io/milestone</url>
                <snapshots>
                    <enabled>false</enabled>
                </snapshots>
            </repository>
            <repository>
                <id>spring-snapshots</id>
                <name>Spring Snapshots</name>
                <url>https://repo.spring.io/snapshot</url>
                <releases>
                    <enabled>false</enabled>
                </releases>
            </repository>
        </repositories>

        <dependencyManagement>
            <dependencies>
                <dependency>
                    <groupId>org.springframework.ai</groupId>
                    <artifactId>spring-ai-bom</artifactId>
                    <version>1.0.0-SNAPSHOT</version>
                    <type>pom</type>
                    <scope>import</scope>
                </dependency>
            </dependencies>
        </dependencyManagement>

        <build>
            <plugins>
                <plugin>
                    <groupId>org.springframework.boot</groupId>
                    <artifactId>spring-boot-maven-plugin</artifactId>
                </plugin>
            </plugins>
        </build>

    </project>
   ```

   Note that this is very similar to the Maven POM files you have created in previous modules.  [Spring AI](https://github.com/spring-projects/spring-ai) is currently approaching its 1.0.0 release, so you need to enable access to the milestone and snapshot repositories to use it.  You will see the `repositories` section in the POM file above does that. 

   The `spring-ai-bom` was added in the `dependencyManagement` section to make it easy to select the correct versions of various dependencies.

   Finally, a dependency for `spring-ai-ollama-spring-boot-starter` was added. This provides access to the Spring AI Ollama functionality and autoconfiguration. 

1. Configure access to your Ollama deployment

   To configure access the Ollama, create a Spring application configuration file
   called `src/main/resources/application.yaml` with the following content:

    ```yaml
    spring:
      application:
        name: chatbot
      ai:
        ollama:
          base-url: http://ollama.ollama.svc.cluster.local:11434
          chat:
            enabled: true
            options:
              model: llama3
    ```

   Note that you are providing the URL to access the Ollama instance that you just
   deployed in your cluster.  You also need to tell Spring AI to enable chat and
   which model to use.

1. Create the main Spring application class

   Create a file called `src/main/java/com/example/chatbot/ChatbotApplication.java` with
   the following content:

    ```java
    package com.example.chatbot;

    import org.springframework.boot.SpringApplication;
    import org.springframework.boot.autoconfigure.SpringBootApplication;

    @SpringBootApplication
    public class ChatbotApplication {

        public static void main(String[] args) {
            SpringApplication.run(ChatbotApplication.class, args);
        }

    }
    ```

    This is a very standard main class which you are likely familiar with from previous modules.

1. Create the Chat Controller

   Create a file called `ChatController.java` in the directory
   `src/main/java/com/example/chatbot/controller` with the following content:

    ```java
    package com.example.chatbot.controller;

    import org.springframework.web.bind.annotation.RequestMapping;
    import org.springframework.web.bind.annotation.RestController;
    import org.springframework.ai.chat.model.ChatModel;
    import org.springframework.ai.chat.model.ChatResponse;
    import org.springframework.ai.chat.prompt.Prompt;
    import org.springframework.ai.ollama.api.OllamaModel;
    import org.springframework.ai.ollama.api.OllamaOptions;
    import org.springframework.web.bind.annotation.PostMapping;
    import org.springframework.web.bind.annotation.RequestBody;

    @RestController
    @RequestMapping("/chat")
    public class ChatController {

        final ChatModel chatModel;

        public ChatController(ChatModel chatModel) {
            this.chatModel = chatModel;
        }

        @PostMapping
        public String chat(@RequestBody String question) {
            
            ChatResponse response = chatModel.call(
                new Prompt(question,
                    OllamaOptions.builder()
                    .withModel(OllamaModel.LLAMA3)
                    .withTemperature(0.4f)
                    .build()
            ));

            return response.getResult().getOutput().getContent();
            
        }
        
    }
    ```

    In this class, you have a `RestController`, which you are likely familiar with  from previous modules, and a `PostMapping` to create an HTTP POST endpoint.

    The `chat()` method reads a question from the HTTP body, makes a call to Ollama using the Llama3 model to get a response and then returns the text part of the response to the user in the HTTP body.

    Notice that a `ChatModel` is injected into this controller to provide access to Ollama's chat interface.

    You may also notice that we set the temperature to 0.4.  Temperature is a parameter of LLMs that controls how creative the answer will be.  Lower numbers (approaching zero) will tend to produce less creative answers, whereas higher numbers will tend to produce more creative answers.

    LLMs are not deterministic, so you will tend to get a different answer each time you ask them the same question, unless the temperature is very low.

### Deploy your application

1. Build a JAR file for deployment

    Run the following command to build the JAR file (it will also remove any earlier builds). 

    ```shell
    $ mvn clean package
    ```

    The service is now ready to deploy to the backend.

1. Prepare the backend for deployment

    The Oracle Backend for Microservices and AI admin service is not exposed outside the Kubernetes cluster by default. Oracle recommends using a **kubectl** port forwarding tunnel to establish a secure connection to the admin service.

    Start a tunnel using this command in a new terminal window:

    ```shell
    $ kubectl -n obaas-admin port-forward svc/obaas-admin 8080
    ```

    Get the password for the `obaas-admin` user. The `obaas-admin` user is the equivalent of the admin or root user in the Oracle Backend for Microservices and AI backend.

    ```shell
    $ kubectl get secret -n azn-server  oractl-passwords -o jsonpath='{.data.admin}' | base64 -d
    ```

    Start the Oracle Backend for Microservices and AI CLI (*oractl*) in a new terminal window using this command:

    ```shell
    $ oractl
     _   _           __    _    ___
    / \ |_)  _.  _. (_    /  |   |
    \_/ |_) (_| (_| __)   \_ |_ _|_
    ========================================================================================
      Application Name: Oracle Backend Platform :: Command Line Interface
      Application Version: (1.3.0)
      :: Spring Boot (v3.3.3) ::

      Ask for help:
      - Slack: https://oracledevs.slack.com/archives/C03ALDSV272
      - email: obaas_ww@oracle.com

    oractl:>
    ```

    Connect to the Oracle Backend for Microservices and AI admin service using the `connect` command. Enter `obaas-admin` and the username and use the password you collected earlier.

    ```shell
    oractl> connect
    username: obaas-admin
    password: **************
    Credentials successfully authenticated! obaas-admin -> welcome to OBaaS CLI.
    oractl:>
    ```

1. Deploy the chatbot

    You will now deploy your chatbot to the Oracle Backend for Microservices and AI using the CLI.  You will deploy into the `application` namespace, and the service name will be `chatbot`.  Run this command to deploy your service, make sure you provide the correct path to your JAR file.  **Note** that this command may take 1-3 minutes to complete:

    ```shell
    oractl:> deploy --app-name application --service-name chatbot --artifact-path /path/to/chatbot-0.0.1-SNAPSHOT.jar --image-version 0.0.1 --java-version ghcr.io/oracle/graalvm-native-image-obaas:21
    uploading: /Users/atael/tmp/cloudbank/chatbot/target/chatbot-0.0.1-SNAPSHOT.jar
    building and pushing image...

    creating deployment and service...
    obaas-cli [deploy]: Application was successfully deployed
    oractl:>
    ```

    > What happens when you use the Oracle Backend for Microservices and AI CLI (*oractl*) **deploy** command? When you run the **deploy** command, the OOracle Backend for Microservices and AI CLI does several things for you:

    * Uploads the JAR file to server side
    * Builds a container image and push it to the OCI Registry
    * Inspects the JAR file and looks for bind resources (JMS)
    * Create the microservices deployment descriptor (k8s) with the resources supplied
    * Applies the k8s deployment and create k8s object service to microservice

### Use your application

The simplest way to verify the application is to use a kubectl tunnel to access it.

1. Create a tunnel to access the application 

   Start a tunnel using this command: 

    ```bash
    kubectl -n application port-forward svc/chatbot 8080 &
    ```

1. Test your application

   Make a POST request through the tunnel to ask the chatbot a question:

    ```bash
    $ curl -X POST -d 'what is spring boot?'  http://localhost:8080/chat
    A popular question!
    
    Spring Boot is an open-source Java-based framework that provides a simple and efficient way to build web applications, RESTful APIs, and microservices. It's built on top of the Spring  Framework, but with a more streamlined and opinionated approach.
    ...
    ...
    ```