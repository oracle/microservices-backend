---
title: "OBaaS CLI"
description: "Command Line Interface for Oracle Backend for Microservices and AI"
keywords: "cli tool deployment spring springboot microservices development oracle backend"
---

The Oracle Backend for Microservices and AI offers a command-line interface (CLI), `oractl`. The CLI commands simplify the deployment of microservices applications as well as bindings with the resources that they use.Download the [CLI here](https://github.com/oracle/microservices-backend/releases/tag/OBAAS-1.4.0). The platform-specific binary can be renamed to `oractl` for convenience.

Table of Contents:

* [Installing the CLI](#installing-the-cli)
* [Using the CLI](#using-the-cli)
* [Command Concepts](#command-concepts)
* [Workflow Example](#workflow-example)
* [Available Command Groups](#available-commands)
  * [Help](#help)
  * [Connect to the backend](#connect)
  * [Manage Artifact](#artifact)
    * [artifact create](#artifact-create)
    * [artifact list](#artifact-list)
    * [artifact delete](#artifact-delete)
    * [artifact deleteByWorkload](#artifact-deletebyworkload)
  * [Manage AutoScaler](#autoscaler)
    * [autoscaler create](#autoscaler-create)
    * [autoscaler list](#autoscaler-list)
    * [autoscaler update](#autoscaler-update)
    * [autoscaler delete](#autoscaler-delete)
  * [Manage Binding](#binding)
    * [binding create](#binding-create)
    * [binding list](#binding-list)
    * [binding get](#binding-get)
    * [binding update](#binding-update)
    * [binding delete](#binding-delete)
  * [Manage Configuration](#configuration)
    * [configuration create](#configuration-create)
    * [configuration list](#configuration-list)
    * [configuration get](#configuration-get)
    * [configuration update](#configuration-update)
    * [configuration delete](#configuration-delete)
  * [Manage Datastore](#datastore)
    * [datastore create](#datastore-create)
    * [datastore list](#datatore-list)
    * [datastore get](#datastore-get)
    * [datastore update](#datastore-update)
    * [datastore delete](#datastore-delete)
  * [Manage Identity](#identity)
    * [user create](#user-create)
    * [user list](#user-list)
    * [user get](#user-get)
    * [user delete](#user-delete)
    * [user change-password](#user-change-password)
    * [user change-roles](#user-change-roles)
  * [Manage Image](#image)
    * [image create](#image-create)
    * [image list](#image-list)
    * [image get](#image-get)
    * [image delete](#image-delete)
    * [image deleteByWorkload](#image-deletebyworkload)
  * [Manage Namespace](#namespace)
    * [namespace create](#namespace-create)
    * [namespace list](#namespace-list)
    * [namespace update](#namespace-update)
    * [namespace delete](#namespace-delete)
  * [Manage Telemetry](#telemetry)
    * [telemetry-consent create](#telemetry-consent-create)
    * [telemetry-consent list](#telemetry-consent-list)
    * [telemetry-consent update](#telemetry-consent-update)
  * [Manage Workload](#workload)
    * [workload create](#workload-create)
    * [workload list](#workload-list)
    * [workload get](#workload-get)
    * [workload getImage](#workload-getimage)
    * [workload update](#workload-update)
    * [workload delete](#workload-delete)
  * [Server Version](#server-version)
* [Logging Information](#logging)

## Installing the CLI

Oracle Backend for Microservices and AI CLI is used to configure your backend and to deploy your Spring Boot applications to the backend.

1. Download the Oracle Backend for Microservices and AI CLI `oractl`

   Download the [CLI from here](https://github.com/oracle/microservices-backend/releases/tag/OBAAS-1.4.0)

1. Rename the downloaded file to `oractl`

1. Add `oractl` to PATH variable

   You need to make sure it is executable and add it to your PATH environment variable.

    ```shell
    <copy>
    chmod +x oractl
    export PATH=/path/to/oractl:$PATH</copy>
    ```

**NOTE:** If environment is a Mac you need run the following command `sudo xattr -r -d com.apple.quarantine <downloaded-file>` otherwise will you get a security warning and the CLI will not work.

## Using the CLI

1. Expose the Oracle Backend for Microservices and AI Admin server that the CLI calls using this command:

    ```bash
    kubectl port-forward services/obaas-admin -n obaas-admin 8080
    ```

2. Start the CLI in interactive mode by running oractl from your terminal window. For example:

    ```bash
    oractl
    ```

    As a result, the `oractl` prompt is displayed as follows:

    ```text
        _   _           __    _    ___
       / \ |_)  _.  _. (_    /  |   |
       \_/ |_) (_| (_| __)   \_ |_ _|_
       ========================================================================================
       Application Name: Oracle Backend Platform :: Command Line Interface
       Application Version: (1.4.0)
       :: Spring Boot (v3.5.4) :: 
       
       Ask for help:
       - Slack: https://oracledevs.slack.com/archives/C06L9CDGR6Z
       - email: obaas_ww@oracle.com

       oractl:>
    ```

## Command Concepts

The following describes the different resources handled by the client:

* Artifacts - An artifact, for example a JAR file, that can be used to run a workload.  Artifacts are built into images.

* Autoscaler - adjust pod replicas in response to workload demands.

* Binding - A binding associates a datastore with a workload.

* Configuration - A configuration property which can be injected into a workload. Identified by name, label and profile.

* Datastore - A data store, for example a pluggable database or a schema/user in a database instance, which can be used by a workload.  Can be shared by multiple workloads, although this is only recommended for truly shared resources like queues/topics used for asynchronous communications between microservices.  In most normal cases, a datastore should only be associated with one workload, in keeping with the "database per service" pattern.

* Identity - APIs related to identity (users, roles, etc.) are collected in this group.

* Image - A container image which can be used to run an workload. Built from an artifact and a base image.

* Namespace - A Kubernetes namespace in which workloads can be deployed.

* Telemetry - APIs for managing consent (opt-in) for sending telemetry data to Oracle.

* Workload - A Spring Boot application which can be deployed in the platform. Is associated with an artifact and an image, which have their own separate lifecycles.

## Workflow Example

Following is a workflow example deploying the Spring services that makeup the CloudBank backend.

Create the namespace for the CloudBank application

```shell
namespace create --namespace application
```

Create the datastore for the Account and Customer microservices

```shell
datastore create --namespace application --username account --id account
datastore create --namespace application --username customer --id customer
```

Upload the Spring microservice jars

```shell
artifact create --namespace application --workload account --imageVersion 0.0.1 --file /Users/devusr/microservices-backend/cloudbank-v4/account/target/account-0.0.1-SNAPSHOT.jar

artifact create --namespace application --workload checks --imageVersion 0.0.1 --file /Users/devusr/microservices-backend/cloudbank-v4/checks/target/checks-0.0.1-SNAPSHOT.jar

artifact create --namespace application --workload customer --imageVersion 0.0.1 --file /Users/devusr/microservices-backend/cloudbank-v4/customer/target/customer-0.0.1-SNAPSHOT.jar

artifact create --namespace application --workload creditscore --imageVersion 0.0.1 --file /Users/devusr/microservices-backend/cloudbank-v4/creditscore/target/creditscore-0.0.1-SNAPSHOT.jar

artifact create --namespace application --workload transfer --imageVersion 0.0.1 --file /Users/devusr/microservices-backend/cloudbank-v4/transfer/target/transfer-0.0.1-SNAPSHOT.jar
```

Create images from the artifacts

```shell
image create --namespace application --workload account --imageVersion 0.0.1
image create --namespace application --workload checks --imageVersion 0.0.1
image create --namespace application --workload customer --imageVersion 0.0.1 
image create --namespace application --workload creditscore --imageVersion 0.0.1 
image create --namespace application --workload transfer --imageVersion 0.0.1 
```

Create a workload for the images

```shell
workload create --namespace application --imageVersion 0.0.1 --id account --liquibaseDB admin --cpuRequest 100m --framework SPRING_BOOT
workload create --namespace application --imageVersion 0.0.1 --id checks --cpuRequest 100m
workload create --namespace application --imageVersion 0.0.1 --id customer --liquibaseDB admin --cpuRequest 100m --framework SPRING_BOOT
workload create --namespace application --imageVersion 0.0.1 --id creditscore --cpuRequest 100m --framework SPRING_BOOT
workload create --namespace application --imageVersion 0.0.1 --id transfer --cpuRequest 100m --framework SPRING_BOOT
```

Create a binding between the workload and the datastore

```shell
binding create --namespace application --datastore account --workload account --framework SPRING_BOOT
binding create --namespace application --datastore customer --workload customer --framework SPRING_BOOT
binding create --namespace application --datastore account --workload checks --framework SPRING_BOOT
```

Verify success

```shell
serverversion
namespace list
datastore list --namespace application
artifact list
image list
binding list --namespace application
workload list --namespace application
```

## Available Commands

### help

Short descriptions for the available commands can be viewed by issuing the `help` command and detailed help for any individual
commands can be viewed by issuing `help [command-name]`. For example:

```bash
oractl:>help
AVAILABLE COMMANDS

Artifact
       artifact list: Lists the artifacts in your platform.
       artifact create: Creates a new artifact in your platform.
       artifact delete: Delete an artifact in your platform.
       artifact deleteByWorkload: Delete an artifact in your platform by workload.

Binding
       binding list: Lists bindings for a given namespace.
       binding update: Update a specific binding for a given namespace.
       binding delete: Delete a specific binding for a given namespace.
       binding create: Create a binding in a given namespace.
       binding get: Get a specific binding for a given namespace.

Built-In Commands
       help: Display help about available commands
       stacktrace: Display the full stacktrace of the last error.
       clear: Clear the shell screen.
       quit, exit: Exit the shell.
       history: Display or save the history of previously run commands
       version: Show version info
       script: Read and execute commands from a file.

Configuration
       configuration delete: Delete a specific configuration key.
       configuration create: Create a configuration.
       configuration get: Get a specific configuration by name.
       configuration update: Update a configuration.
       configuration list: Lists all configuration.

Datastore
       datastore list: Lists datastores for a given namespace.
       datastore update: Update a specific datastore for a given namespace.
       datastore create: Create a datastore in a given namespace.
       datastore delete: Delete a specific datastore for a given namespace.
       datastore get: Get a specific datastore for a given namespace.

Identity
       user list: Lists all the users in your platform.
       user create: Creates a new user in your platform.
       user get: get a user on your platform.
       user delete: Delete a user in your platform.
       user change-roles: Change the roles from the specified user.
       user change-password: Change password for the specified user. 

Image
       image get: Get a specific image on your platform.
       image list: Lists all the images in your platform.
       image create: Creates a new image in your platform.
       image delete: Delete an image in your platform.
       image deleteByWorkload: Delete an image in your platform by workload.

Initialization
       connect: Connect to the OBaaS Admin Service.

Namespace
       namespace create: Creates a new namespace in your platform.
       namespace delete: Delete a namespace in your platform.
       namespace update: Update the namespace secrets.
       namespace list: Lists the namespaces in your platform.

Server Version
       serverversion: Get obaas admin server version.

Telemetry
       telemetry-consent update: Update the platforms telemetry consent.
       telemetry-consent list: Lists the platforms telemetry consent status.
       telemetry-consent create: Create a telemetry consent record.

Workload
       autoscaler delete: Delete an autoscaler for a specific workload in a given namespace.
       workload create: Create a workload in a given namespace.
       workload delete: Delete a specific workload for a given namespace.
       workload update: Update a specific workload for a given namespace.
       autoscaler create: Create an autoscaler for a specific workload in a given namespace.
       workload getImage: Get the image for a specific workload in a given namespace.
       workload list: Lists workloads for a given namespace.
       workload get: Get a specific workload for a given namespace.
       autoscaler list: Lists autoscalers for a given workload in a given namespace.
       autoscaler update: Update an autoscaler for a specific workload in a given namespace.


Ask for Help
       Slack: https://oracledevs.slack.com/archives/C03ALDSV272
       E-mail: obaas_ww@oracle.com
```

The following is a description of the CLI commands:

## Connect

Use the `connect` command to connect your `oractl` CLI to the Oracle Backend Administration service:

```bash
oractl:>help connect
NAME
       connect - Connect to the OBaaS Spring Cloud admin console.

SYNOPSIS
       connect --url String --help

OPTIONS
       --url String
       admin server URL
       [Optional, default = http://localhost:8080]

       --help or -h
       help for connect
       [Optional]

Ask for Help
       Slack: https://oracledevs.slack.com/archives/C03ALDSV272
       E-mail: obaas_ww@oracle.com

   ```

For example:

```bash
oractl:>connect
? username obaas-admin
? password ****************
obaas-admin -> Welcome!
```

## Artifact

An artifact, for example a JAR file, that can be used to run a workload.  Artifacts are built into images.

### artifact create

```bash
oractl:>help artifact create
NAME
       artifact create - Creates a new artifact in your platform.

SYNOPSIS
       artifact create [--namespace String] [--workload String] [--imageVersion String] --nativeImage boolean --path String [--file String] --help 

OPTIONS
       --namespace String
       The namespace the artifact will be created in.
       [Mandatory]

       --workload String
       The workload name for the artifact.
       [Mandatory]

       --imageVersion String
       The version  of the artifact.
       [Mandatory]

       --nativeImage boolean
       Whether to create a native artifact.
       [Optional, default = false]

       --path String
       Artifact Path.
       [Optional]

       --file String
       Jar file used for Artifact Creation.
       [Mandatory]

       --help or -h 
       help for artifact create
       [Optional]

```

   For example:

   ```bash
oractl:>artifact create --namespace myapp --workload account  --imageVersion 1.0.0 --file /Users/devuser/account.jar
obaas-cli [artifact create]: Artifact [account:1.0.0] was successfully created.
   ```

### artifact list

```bash
oractl:>help artifact list
NAME
       artifact list - Lists the artifacts in your platform.

SYNOPSIS
       artifact list --help 

OPTIONS
       --help or -h 
       help for artifact list
       [Optional]

```

   For example:

   ```shell
   oractl:>artifact list
╔══╤═════════╤════════╤════════╤══════╤══════════════════════════════════════════════════════╗
║ID│Namespace│Workload│Artifact│Native│Path                                                  ║
║  │         │        │Version │Image │                                                      ║
╠══╪═════════╪════════╪════════╪══════╪══════════════════════════════════════════════════════╣
║6 │myapp    │account │1.0.0   │false │/app/upload-dir/myapp/account/target/account-1.0.0.jar║
╚══╧═════════╧════════╧════════╧══════╧══════════════════════════════════════════════════════╝
```

### artifact delete

```bash
oractl:>help artifact delete
NAME
       artifact delete - Delete an artifact in your platform.

SYNOPSIS
       artifact delete [--artifactId String] --help 

OPTIONS
       --artifactId String
       The ID of the artifact you want to delete.
       [Mandatory]

       --help or -h 
       help for artifact delete
       [Optional]
```

For example:

```shell
oractl:>artifact delete --artifactId 6
obaas-cli [artifact delete]: Artifact [6] was successfully deleted.
```

### artifact deleteByWorkload

```bash
oractl:>help artifact deleteByWorkload
NAME
       artifact deleteByWorkload - Delete an artifact in your platform by workload.

SYNOPSIS
       artifact deleteByWorkload [--namespace String] [--workload String] [--artifactVersion String] --help 

OPTIONS
       --namespace String
       The namespace the artifact will be deleted in.
       [Mandatory]

       --workload String
       The workload name for the artifact.
       [Mandatory]

       --artifactVersion String
       The version  of the artifact.
       [Mandatory]

       --help or -h 
       help for artifact deleteByWorkload
       [Optional]

```

For example:

```shell
oractl:>artifact deleteByWorkload --namespace myapp --workload account --artifactVersion 1.0.0
obaas-cli [artifact delete]: Artifact [account:1.0.0] was successfully deleted.
```

## AutoScaler

adjust pod replicas in response to workload demands

### autoscaler create

```bash
oractl:>help autoscaler create
NAME
       autoscaler create - Create an autoscaler for a specific workload in a given namespace.

SYNOPSIS
       autoscaler create [--namespace String] [--workloadID String] [--minimumReplicas Integer] [--maximumReplicas Integer] [--cpuPercent Integer] --help 

OPTIONS
       --namespace String
       The namespace to create the workload in.
       [Mandatory]

       --workloadID String
       The id of the workload.
       [Mandatory]

       --minimumReplicas Integer
       Minimum replicas for workload.
       [Mandatory]

       --maximumReplicas Integer
       Maximum Replicas for workload.
       [Mandatory]

       --cpuPercent Integer
       Indicates the average CPU utilization threshold that triggers scaling of pods.
       [Mandatory]

       --help or -h 
       help for autoscaler create
       [Optional]
```

For example:

```bash
oractl:>autoscaler create --namespace myapp --workloadID account --minimumReplicas 1 --maximumReplicas 5 --cpuPercent 65
obaas-cli [autoscaler create]: Autoscaler [account] was successfully created.
```

### autoscaler list

```bash
oractl:>help autoscaler list
NAME
       autoscaler list - Lists autoscalers for a given workload in a given namespace.

SYNOPSIS
       autoscaler list [--namespace String] [--workloadID String] --help 

OPTIONS
       --namespace String
       The namespace to query workloads from.
       [Mandatory]

       --workloadID String
       The id of the workload.
       [Mandatory]

       --help or -h 
       help for autoscaler list
       [Optional]
```

For example:

```bash
oractl:>autoscaler list --namespace myapp --workloadID accounts
╔═══════════╤═══════════╤══════════╗
║Minimum    │Maximum    │CPUPercent║
║Replicas   │Replicas   │          ║
╠═══════════╪═══════════╪══════════╣
║1          │5          │65        ║
╚═══════════╧═══════════╧══════════╝
```

### autoscaler update

```bash
oractl:>help autoscaler update
NAME
       autoscaler update - Update an autoscaler for a specific workload in a given namespace.

SYNOPSIS
       autoscaler update [--namespace String] [--workloadID String] [--minimumReplicas Integer] [--maximumReplicas Integer] [--cpuPercent Integer] --help 

OPTIONS
       --namespace String
       The namespace to create the workload in.
       [Mandatory]

       --workloadID String
       The id of the workload.
       [Mandatory]

       --minimumReplicas Integer
       Minimum replicas for workload.
       [Mandatory]

       --maximumReplicas Integer
       Maximum Replicas for workload.
       [Mandatory]

       --cpuPercent Integer
       Indicates the average CPU utilization threshold that triggers scaling of pods.
       [Mandatory]

       --help or -h 
       help for autoscaler update
       [Optional]
```

For example:

```bash
oractl:>autoscaler update --namespace myapp --workloadID account --minimumReplicas 2 --maximumReplicas 3 --cpuPercent 75
obaas-cli [autoscaler update]: Autoscaler [account] was successfully updated.
```

### autoscaler delete

```bash
oractl:>help autoscaler delete
NAME
       autoscaler delete - Delete an autoscaler for a specific workload in a given namespace.

SYNOPSIS
       autoscaler delete [--namespace String] [--workloadID String] --help 

OPTIONS
       --namespace String
       The namespace of the workload.
       [Mandatory]

       --workloadID String
       The workload id that has the autoscaler to be deleted.
       [Mandatory]

       --help or -h 
       help for autoscaler delete
       [Optional]
```

For example:

```bash
oractl:>autoscaler delete --namespace myapp --workloadID accounts
obaas-cli [autoscaler delete]: Autoscaler [accounts] was successfully deleted.
```

## Binding

A binding associates a datastore with a workload.

### binding create

```bash
oractl:>help binding create
NAME
       binding create - Create a binding in a given namespace.

SYNOPSIS
       binding create [--namespace String] [--workload String] [--datastore String] [--framework String]--help 

OPTIONS
       --namespace String
       The namespace to create the binding in.
       [Mandatory]

       --workload String
       The workload id.
       [Mandatory]

       --datastore String
       The datastore id.
       [Mandatory]

       --framework String
       The workload framework. Must be SPRING_BOOT or HELIDON
       [Mandatory]

       --help or -h 
       help for binding create
       [Optional]
```

For example:

```bind
oractl:>binding create --namespace myapp --workload accounts --datastore mydatastore --framework SPRING_BOOT
obaas-cli [binding create]: Binding [accounts] was successfully created.
```

### binding list

```bash
oractl:>help binding list
NAME
       binding list - Lists bindings for a given namespace.

SYNOPSIS
       binding list [--namespace String] --help 

OPTIONS
       --namespace String
       The namespace to query bindings from.
       [Mandatory]

       --help or -h 
       help for binding list
       [Optional]
```

For example:

```bash
oractl:>binding list --namespace myapp
╔════════════════╤═════════╤═══════════╗
║Workload        │Datastore│Framework  ║
╠════════════════╪═════════╪═══════════╣
║account         │account  │SPRING_BOOT║
╟────────────────┼─────────┼───────────╢
║checks          │account  │SPRING_BOOT║
╟────────────────┼─────────┼───────────╢
║customer        │customer │SPRING_BOOT║
╟────────────────┼─────────┼───────────╢
║testrunner      │account  │SPRING_BOOT║
╟────────────────┼─────────┼───────────╢
║customer-helidon│customer │HELIDON.   ║
╚════════════════╧═════════╧═══════════╝
```

### binding get

```bash
oractl:>help binding get
NAME
       binding get - Get a specific binding for a given namespace.

SYNOPSIS
       binding get [--namespace String] [--workload String] --help 

OPTIONS
       --namespace String
       The namespace to query the binding from.
       [Mandatory]

       --workload String
       The workload id.
       [Mandatory]

       --help or -h 
       help for binding get
       [Optional]
```

For example:

```bash
oractl:>binding get --namespace myapp --workload account
╔════════╤═════════╤═══════════╗
║Workload│Datastore│Framework  ║
╠════════╪═════════╪═══════════╣
║account │account  │SPRING_BOOT║
╚════════╧═════════╧═══════════╝
```

### binding update

```bash
oractl:>help binding update
NAME
       binding update - Update a specific binding for a given namespace.

SYNOPSIS
       binding update [--namespace String] [--workload String] [--datastore String] [--framework String] --help 

OPTIONS
       --namespace String
       The namespace to update the datastore in.
       [Mandatory]

       --workload String
       The workload id.
       [Mandatory]

       --datastore String
       The datastore id.
       [Mandatory]

       --framework String
       The workload framework. Must be SPRING_BOOT or HELIDON
       [Mandatory]

       --help or -h 
       help for binding update
       [Optional]
```

For example:

```bash
oractl:>binding update --namespace myapp --workload account --datastore newdatastore --framework SPRING_BOOT
obaas-cli [binding update]: Binding [account] was successfully updated.
```

### binding delete

```bash
oractl:>help binding delete
NAME
       binding delete - Delete a specific binding for a given namespace.

SYNOPSIS
       binding delete [--namespace String] [--workload String] --help 

OPTIONS
       --namespace String
       The namespace to delete the binding in.
       [Mandatory]

       --workload String
       The workload id.
       [Mandatory]

       --help or -h 
       help for binding delete
       [Optional]
```

For example:

```bash
oractl:>binding delete --namespace myapp --workload account
obaas-cli [binding delete]: Binding [account] was successfully deleted.
```

## Configuration

A configuration property which can be injected into a workload. Identified by name, label and profile.

### configuration create

```bash
oractl:>help configuration create
NAME
       configuration create - Create a configuration.

SYNOPSIS
       configuration create [--name String] [--profile String] [--label String] [--key String] [--value String] --help 

OPTIONS
       --name String
       The name of the configuration.
       [Mandatory]

       --profile String
       The configuration profile.
       [Mandatory]

       --label String
       The configuration label.
       [Mandatory]

       --key String
       The configuration key.
       [Mandatory]

       --value String
       The configuration value.
       [Mandatory]

       --help or -h 
       help for configuration create
       [Optional]
```

For example:

```bash
oractl:>configuration create --name accountconfig --profile development --label 23beta --key debuglogging --value debug
obaas-cli [configuration create]: Configuration [accountconfig] was successfully created.
```

### configuration list

```bash
oractl:>help configuration list
NAME
       configuration list - Lists all configuration.

SYNOPSIS
       configuration list --help 

OPTIONS
       --help or -h 
       help for configuration list
       [Optional]
```

For example:

```bash
oractl:>configuration list
╔═════════════╗
║Name         ║
╠═════════════╣
║accountconfig║
╟─────────────╢
║application-a║
╚═════════════╝
```

### configuration get

```bash
oractl:>help configuration get
NAME
       configuration get - Get a specific configuration by name.

SYNOPSIS
       configuration get [--name String] --help 

OPTIONS
       --name String
       The name of the configuration.
       [Mandatory]

       --help or -h 
       help for configuration get
       [Optional]
```

For example:

```bash
oractl:>configuration get --name accountconfig
╔═════════════╤═══════════╤══════╤════════════╤═════╗
║Name         │Profile    │Label │Key         │Value║
╠═════════════╪═══════════╪══════╪════════════╪═════╣
║accountconfig│development│23beta│debuglogging│debug║
╚═════════════╧═══════════╧══════╧════════════╧═════╝
```

### configuration update

```bash
oractl:>help configuration update
NAME
       configuration update - Update a configuration.

SYNOPSIS
       configuration update [--name String] [--profile String] [--label String] [--key String] [--value String] --help 

OPTIONS
       --name String
       The name of the configuration.
       [Mandatory]

       --profile String
       The configuration profile.
       [Mandatory]

       --label String
       The configuration label.
       [Mandatory]

       --key String
       The configuration key.
       [Mandatory]

       --value String
       The configuration value.
       [Mandatory]

       --help or -h 
       help for configuration update
       [Optional]
```

For example:

```bash
oractl:>configuration update --name accountconfig --profile development --label 23beta --key debuglogging --value info
obaas-cli [configuration update]: Configuration [accountconfig] was successfully updated.
```

### configuration delete

```bash
oractl:>help configuration delete
NAME
       configuration delete - Delete a specific configuration key.

SYNOPSIS
       configuration delete [--name String] [--profile String] [--label String] [--key String] [--value String] --help 

OPTIONS
       --name String
       The name of the configuration.
       [Mandatory]

       --profile String
       The configuration profile.
       [Mandatory]

       --label String
       The configuration label.
       [Mandatory]

       --key String
       The configuration key.
       [Mandatory]

       --value String
       The configuration value.
       [Mandatory]

       --help or -h 
       help for configuration delete
       [Optional]
```

For example:

```bash
oractl:>configuration delete --name accountconfig --profile development --label 23beta --key debuglogging --value info
obaas-cli [configuration delete]: Configuration [accountconfig] was successfully deleted.
```

## DataStore

A data store, for example a pluggable database or a schema/user in a database instance, which can be used by a workload.  Can be shared by multiple workloads, although this is only recommended for truly shared resources like queues/topics used for asynchronous communications between microservices.  In most normal cases, a datastore should only be associated with one workload, in keeping with the "database per service" pattern.

### datastore create

```bash
oractl:>help datastore create
NAME
       datastore create - Create a datastore in a given namespace.

SYNOPSIS
       datastore create [--namespace String] [--username String] [--id String] --help 

OPTIONS
       --namespace String
       The namespace to create the datastore in.
       [Mandatory]

       --username String
       The datastore username.
       [Mandatory]

       --id String
       The datastore id.
       [Mandatory]

       --help or -h 
       help for datastore create
       [Optional]

```

For example:

```bash
oractl:>datastore create --namespace myapp --username account --id account
? password ************
obaas-cli [datastore create]: Datastore [account] was successfully created.
```

### datatore list

```bash
oractl:>help datastore list
NAME
       datastore list - Lists datastores for a given namespace.

SYNOPSIS
       datastore list [--namespace String] --help 

OPTIONS
       --namespace String
       The namespace to query datastores from.
       [Mandatory]

       --help or -h 
       help for datastore list
       [Optional]
```

For example:

```shell
oractl:>datastore list --namespace myapp
╔════════════╤════════╗
║Datastore ID│Username║
╠════════════╪════════╣
║account     │account ║
╟────────────┼────────╢
║mydatastore │dbuser  ║
╚════════════╧════════╝
```

### datastore get

```bash
oractl:>help datastore get
NAME
       datastore get - Get a specific datastore for a given namespace.

SYNOPSIS
       datastore get [--namespace String] [--id String] --help 

OPTIONS
       --namespace String
       The namespace to query the datastore from.
       [Mandatory]

       --id String
       The datastore id.
       [Mandatory]

       --help or -h 
       help for datastore get
       [Optional]

```

For example:

```bash
oractl:>datastore get --namespace myapp --id account
╔════════════╤════════╗
║Datastore ID│Username║
╠════════════╪════════╣
║account     │account ║
╚════════════╧════════╝
```

### datastore update

```bash
oractl:>help datastore update
NAME
       datastore update - Update a specific datastore for a given namespace.

SYNOPSIS
       datastore update [--namespace String] [--id String] --help 

OPTIONS
       --namespace String
       The namespace to update the datastore in.
       [Mandatory]

       --id String
       The datastore id.
       [Mandatory]

       --help or -h 
       help for datastore update
       [Optional]
```

For example:

```bash
oractl:>datastore update --namespace myapp --id account
? password *************
obaas-cli [datastore update]: Datastore [account] was successfully updated.
```

### datastore delete

```bash
oractl:>help datastore delete
NAME
       datastore delete - Delete a specific datastore for a given namespace.

SYNOPSIS
       datastore delete [--namespace String] [--id String] --help 

OPTIONS
       --namespace String
       The namespace to delete the datastore from.
       [Mandatory]

       --id String
       The datastore id.
       [Mandatory]

       --help or -h 
       help for datastore delete
       [Optional]
```

For example:

```bash
oractl:>datastore delete --namespace myapp --id account
obaas-cli [datastore delete]: Datastore [account] was successfully deleted.
```

## Identity

APIs related to identity (users, roles, etc.) are collected in this group.

### user create

```bash
oractl:>help user create
NAME
       user create - Creates a new user in your platform.

SYNOPSIS
       user create [--username String] --roles String --help 

OPTIONS
       --username String
       The name you assign to the user during creation. This is the user's login for the CLI. The name must be unique across all users in the platform and cannot be changed.
       [Mandatory]

       --roles String
       The user's role within the platform. A user must have up to three possible roles provided in a comma-separated list. [ROLE_ADMIN,ROLE_CONFIG_EDITOR,ROLE_USER,ROLE_SOC_USER].
       [Optional, default = ROLE_USER]

       --help or -h 
       help for user create
       [Optional]
```

For example:

```bash
oractl:>user create --username devuser --roles ROLE_CONFIG_EDITOR,ROLE_USER
? password ************
obaas-cli [user create]: User [devuser] was successfully created.
```

### user list

```bash
oractl:>help user list
NAME
       user list - Lists all the users in your platform.

SYNOPSIS
       user list --help 

OPTIONS
       --help or -h 
       help for user list
       [Optional]
```

For example:

```bash
oractl:>user list
╔════════════╤═════════════════════════════════════════════════════╗
║Username    │Roles                                                ║
╠════════════╪═════════════════════════════════════════════════════╣
║devuser     │ROLE_CONFIG_EDITOR,ROLE_USER                         ║
╟────────────┼─────────────────────────────────────────────────────╢
║obaas-user  │ROLE_USER                                            ║
╟────────────┼─────────────────────────────────────────────────────╢
║obaas-admin │ROLE_ADMIN,ROLE_CONFIG_EDITOR,ROLE_USER,ROLE_SOC_USER║
╟────────────┼─────────────────────────────────────────────────────╢
║obaas-config│ROLE_CONFIG_EDITOR,ROLE_USER                         ║
╚════════════╧═════════════════════════════════════════════════════╝
```

### user get

```bash
oractl:>help user get
NAME
       user get - get a user on your platform.

SYNOPSIS
       user get [--username String] --help 

OPTIONS
       --username String
       The username you want to retrieve.
       [Mandatory]

       --help or -h 
       help for user get
       [Optional]
```

For example:

```bash
oractl:>user get --username devuser
╔════════╤════════════════════════════╗
║Username│Roles                       ║
╠════════╪════════════════════════════╣
║devuser │ROLE_CONFIG_EDITOR,ROLE_USER║
╚════════╧════════════════════════════╝
```

### user change-password

```bash
oractl:>help user change-password
NAME
       user change-password - Change password for the specified user. 

SYNOPSIS
       user change-password [--username String] --help 

OPTIONS
       --username String
       The username you want to change the password.
       [Mandatory]

       --help or -h 
       help for user change-password
       [Optional]
```

For example:

```bash
oractl:>user change-password --username devuser
? password **************
obaas-cli [user update]: User [devuser] was successfully updated.
```

### user change-roles

```bash
oractl:>help user change-roles
NAME
       user change-roles - Change the roles from the specified user.

SYNOPSIS
       user change-roles [--username String] --roles String --help 

OPTIONS
       --username String
       The name you assign to the user during creation. This is the user's login for the CLI.
       [Mandatory]

       --roles String
       The user's role within the platform. A user must have up to three possible roles provided in a comma-separated list. [ROLE_ADMIN,ROLE_CONFIG_EDITOR,ROLE_USER].
       [Optional, default = ROLE_USER]

       --help or -h 
       help for user change-roles
       [Optional]
```

For example:

```bash
oractl:>user change-roles --username devuser --roles ROLE_USER
obaas-cli [user update]: User [devuser] was successfully updated.
```

### user delete

```bash
oractl:>help user delete
NAME
       user delete - Delete a user in your platform.

SYNOPSIS
       user delete [--username String] --help 

OPTIONS
       --username String
       The username you want to delete.
       [Mandatory]

       --help or -h 
       help for user delete
       [Optional]
```

For example:

```bash
oractl:>user delete --username devuser
obaas-cli [user delete]: User [devuser] was successfully deleted.
```

## Image

A container image which can be used to run an workload. Built from an artifact and a base image.
The default base image is ghcr.io/oracle/openjdk-image-obaas:21

### image create

```bash
oractl:>help image create
NAME
       image create - Creates a new image in your platform.

SYNOPSIS
       image create [--namespace String] [--workload String] [--imageVersion String] --baseImage String --nativeImage Boolean --help 

OPTIONS
       --namespace String
       The namespace for the image. 
       [Mandatory]

       --workload String
       The workload name of the artifact for image creation. 
       [Mandatory]

       --imageVersion String
       The version of the artifact for image creation.
       [Mandatory]

       --baseImage String
       The java version used for image creation.
       [Optional, default = ghcr.io/oracle/openjdk-image-obaas:21]

       --nativeImage Boolean
       Whether to create a native artifact.
       [Optional, default = false]

       --help or -h 
       help for image create
       [Optional]

```

For example:

```bash
oractl:>image create --namespace myapp --workload account --imageVersion 1.1.0
obaas-cli [image create]: Image [account:1.1.0] was successfully created.
```

### image list

```bash
oractl:>help image list
NAME
       image list - Lists all the images in your platform.

SYNOPSIS
       image list --help 

OPTIONS
       --help or -h 
       help for image list
       [Optional]
```

For example:

```shell
oractl:>image list
╔══╤═══════════════════════════════════════════════════╤═════════════════════════════════════╤═══════════╤════════╤═════════════════════════════╤═══════╗
║ID│Name                                               │BaseImage                            │Namespace  │Workload│Created                      │Status ║
╠══╪═══════════════════════════════════════════════════╪═════════════════════════════════════╪═══════════╪════════╪═════════════════════════════╪═══════╣
║10│iad.ocir.io/maacloud/calf/application-account:0.0.1│ghcr.io/oracle/openjdk-image-obaas:21│application│account │2024-12-13T14:31:58.041+00:00│FAILED ║
╟──┼───────────────────────────────────────────────────┼─────────────────────────────────────┼───────────┼────────┼─────────────────────────────┼───────╢
║11│iad.ocir.io/maacloud/calf/myapp-account:0.0.1      │ghcr.io/oracle/openjdk-image-obaas:21│myapp      │account │2024-12-13T14:32:22.436+00:00│FAILED ║
╟──┼───────────────────────────────────────────────────┼─────────────────────────────────────┼───────────┼────────┼─────────────────────────────┼───────╢
║12│iad.ocir.io/maacloud/calf/myapp-account:1.1.0      │ghcr.io/oracle/openjdk-image-obaas:21│myapp      │account │2024-12-13T14:42:19.462+00:00│CREATED║
╚══╧═══════════════════════════════════════════════════╧═════════════════════════════════════╧═══════════╧════════╧═════════════════════════════╧═══════╝
```

### image get

```bash
oractl:>help image get
NAME
       image get - Get a specific image on your platform.

SYNOPSIS
       image get [--imageId String] --help 

OPTIONS
       --imageId String
       The ID of the image you want to retrieve.
       [Mandatory]

       --help or -h 
       help for image get
       [Optional]

```

For example:

```bash
oractl:>image get --imageId 12
╔══╤═════════════════════════════════════════════╤═════════════════════════════════════╤═════════╤════════╤═════════════════════════════╤═══════╗
║ID│Name                                         │BaseImage                            │Namespace│Workload│Created                      │Status ║
╠══╪═════════════════════════════════════════════╪═════════════════════════════════════╪═════════╪════════╪═════════════════════════════╪═══════╣
║12│iad.ocir.io/maacloud/calf/myapp-account:1.1.0│ghcr.io/oracle/openjdk-image-obaas:21│myapp    │account │2024-12-13T14:42:19.462+00:00│CREATED║
╚══╧═════════════════════════════════════════════╧═════════════════════════════════════╧═════════╧════════╧═════════════════════════════╧═══════╝
```

### image delete

```bash
oractl:>help image delete
NAME
       image delete - Delete an image in your platform.

SYNOPSIS
       image delete [--imageId String] --help 

OPTIONS
       --imageId String
       The ID of the image you want to delete.
       [Mandatory]

       --help or -h 
       help for image delete
       [Optional]

```

For example:

```bash
oractl:>image delete --imageId 10
obaas-cli [image delete]: Image [10] was successfully deleted.
```

### image deleteByWorkload

> **_NOTE:_**  When using this command the `workload` must still exist. If not you'll get an error. The solution is to [delete the workload using the id](#image-delete).

The error message is similar to this:

```log
obaas-cli [image delete]: error: deployments.apps "account" not found    Http Return Code = 404
```

```bash
oractl:>help image deleteByWorkload
NAME
       image deleteByWorkload - Delete an image in your platform by workload.

SYNOPSIS
       image deleteByWorkload [--namespace String] [--workload String] --help 

OPTIONS
       --namespace String
       The namespace the image will be deleted in.
       [Mandatory]

       --workload String
       The workload name for the image.
       [Mandatory]

       --help or -h 
       help for image deleteByWorkload
       [Optional]
```

For example:

```bash
oractl:>image deleteByWorkload --namespace myapp --workload account
obaas-cli [image delete]: Image [account] was successfully deleted.
```

## Namespace

A Kubernetes namespace in which workloads can be deployed.

### namespace create

```bash
oractl:>help namespace create
NAME
       namespace create - Creates a new namespace in your platform.

SYNOPSIS
       namespace create [--namespace String] --help 

OPTIONS
       --namespace String
       The name for the new namespace in your platform. 
       [Mandatory]

       --help or -h 
       help for namespace create
       [Optional]
```

For example:

```shell
oractl:>namespace create --namespace application
obaas-cli [namespace create]: Namespace [application] was successfully created.
```

### namespace list

```bash
oractl:>help namespace list
NAME
       namespace list - Lists the namespaces in your platform.

SYNOPSIS
       namespace list --help 

OPTIONS
       --help or -h 
       help for namespace list
       [Optional]

```

For example:

```bash
oractl:>namespace list
╔═══════════╗
║Namespace  ║
╠═══════════╣
║application║
╟───────────╢
║myapp      ║
╚═══════════╝
```  

### namespace update

```bash
oractl:>help namespace update
NAME
       namespace update - Update the namespace secrets.

SYNOPSIS
       namespace update [--namespace String] --help 

OPTIONS
       --namespace String
       The namespace you want to update.
       [Mandatory]

       --help or -h 
       help for namespace update
       [Optional]
```

For example:

```bash
oractl:>namespace update --namespace application
obaas-cli [namespace update]: Namespace [application] was successfully updated.
```

### namespace delete

```bash
oractl:>help namespace delete
NAME
       namespace delete - Delete a namespace in your platform.

SYNOPSIS
       namespace delete [--namespace String] --help 

OPTIONS
       --namespace String
       The namespace you want to delete.
       [Mandatory]

       --help or -h 
       help for namespace delete
       [Optional]
```

For example

```bash
oractl:>namespace delete --namespace application
obaas-cli [namespace delete]: Namespace [application] was successfully deleted.
```

## Telemetry

APIs for managing consent (opt-in) for sending telemetry data to Oracle.

### telemetry-consent create

```bash
oractl:>help telemetry-consent create
NAME
       telemetry-consent create - Create a telemetry consent record.

SYNOPSIS
       telemetry-consent create --consented boolean --help 

OPTIONS
       --consented boolean
       The value of the telemetry consent.
       [Optional, default = false]

       --help or -h 
       help for telemetry-consent create
       [Optional]
```

For example:

```bash
oractl:>telemetry-consent create --consented true
obaas-cli [telemetry-consent create]: Telemetry-consent [true] was successfully created.
```

### telemetry-consent list

```shell
oractl:>help telemetry-consent list
NAME
       telemetry-consent list - Lists the platforms telemetry consent status.

SYNOPSIS
       telemetry-consent list --help 

OPTIONS
       --help or -h 
       help for telemetry-consent list
       [Optional]
```

For example:

```bash
oractl:>telemetry-consent list
╔═════════╤═════════════════════════════╗
║Consented│Timestamp                    ║
╠═════════╪═════════════════════════════╣
║true     │2024-12-16T17:32:07.038+00:00║
╚═════════╧═════════════════════════════╝
```

### telemetry-consent update

```bash
oractl:>help telemetry-consent update
NAME
       telemetry-consent update - Update the platforms telemetry consent.

SYNOPSIS
       telemetry-consent update --consented boolean --help 

OPTIONS
       --consented boolean
       The value of the telemetry consent.
       [Optional, default = false]

       --help or -h 
       help for telemetry-consent update
       [Optional]
```

For example:

```bash
oractl:>telemetry-consent update --consented false
obaas-cli [telemetry-consent update]: Telemetry-consent [false] was successfully updated.
```

## Workload

A Spring Boot application which can be deployed in the platform. Is associated with an artifact and an image, which have their own separate lifecycles.

### workload create

```bash
oractl:>help workload create
NAME
       workload create - Create a workload in a given namespace.

SYNOPSIS
       workload create [--namespace String] [--id String] --profile String [--imageVersion String] --cpuRequest String --port int --addHealthProbe boolean --liquibaseDB String --initialReplicas int --help --framework

OPTIONS
       --namespace String
       The namespace to create the workload in.
       [Mandatory]

       --id String
       The id of the workload.
       [Mandatory]

       --profile String
       The workload profile.
       [Optional, default = obaas]

       --imageVersion String
       The workload image version.
       [Mandatory]

       --cpuRequest String
       The workload cpu request.
       [Optional, default = 500m]

       --port int
       Port workload listens on.
       [Optional, default = 8080]

       --addHealthProbe boolean
       The workload cpu request.
       [Optional, default = false]

       --liquibaseDB String
       The workload liquibase database.
       [Optional]

       --initialReplicas int
       Initial workload replicas.
       [Optional, default = 1]

       --framework String
       The workload framework. Must be SPRING_BOOT or HELIDON
       [Mandatory]

       --help or -h 
       help for workload create
       [Optional]
```

For example:

```bash
oractl:>workload create --namespace myapp --imageVersion 1.1.0  --id account
obaas-cli [workload create]: Workload [account] was successfully created.
```

### workload list

```bash
oractl:>help workload list
NAME
       workload list - Lists workloads for a given namespace.

SYNOPSIS
       workload list [--namespace String] --help 

OPTIONS
       --namespace String
       The namespace to query workloads from.
       [Mandatory]

       --help or -h 
       help for workload list
       [Optional]
```

For example:

```bash
oractl:>workload list --namespace myapp
╔═══════════╤════════╤═══════╤══════════╤════╤══════════════╤═══════════════╤═══════════╤═══════════╗
║Workload ID│Workload│Profile│CPURequest│Port│addHealthProbe│initialReplicas│liquibaseDB│Framework  ║
║           │Version │       │          │    │              │               │           │           ║
╠═══════════╪════════╪═══════╪══════════╪════╪══════════════╪═══════════════╪═══════════╪═══════════╣
║account    │0.0.1   │obaas  │100m      │8080│false         │1              │admin      │SPRING_BOOT║
╟───────────┼────────┼───────┼──────────┼────┼──────────────┼───────────────┼───────────┼───────────╢
║checks     │0.0.1   │obaas  │100m      │8080│false         │1              │           │SPRING_BOOT║
╟───────────┼────────┼───────┼──────────┼────┼──────────────┼───────────────┼───────────┼───────────╢
║creditscore│0.0.1   │obaas  │100m      │8080│false         │1              │           │SPRING_BOOT║
╟───────────┼────────┼───────┼──────────┼────┼──────────────┼───────────────┼───────────┼───────────╢
║customer   │0.0.1   │obaas  │100m      │8080│false         │1              │admin      │SPRING_BOOT║
╟───────────┼────────┼───────┼──────────┼────┼──────────────┼───────────────┼───────────┼───────────╢
║testrunner │0.0.1   │obaas  │100m      │8080│false         │1              │           │SPRING_BOOT║
╟───────────┼────────┼───────┼──────────┼────┼──────────────┼───────────────┼───────────┼───────────╢
║transfer   │0.0.1   │obaas  │100m      │8080│false         │1              │           │SPRING_BOOT║
╚═══════════╧════════╧═══════╧══════════╧════╧══════════════╧═══════════════╧═══════════╧═══════════╝
```

### workload get

```bash
oractl:>help workload get
NAME
       workload get - Get a specific workload for a given namespace.

SYNOPSIS
       workload get [--namespace String] [--id String] --help 

OPTIONS
       --namespace String
       The namespace to query the workload from.
       [Mandatory]

       --id String
       The workload id.
       [Mandatory]

       --help or -h 
       help for workload get
       [Optional]
```

For example:

```bash
oractl:>workload get --namespace myapp --id account
╔════════╤════════╤═══════╤══════════╤════╤══════════════╤═══════════════╤═══════════╤═══════════╗
║Workload│Workload│Profile│CPURequest│Port│addHealthProbe│initialReplicas│liquibaseDB│Framework  ║
║ID      │Version │       │          │    │              │               │           │           ║
╠════════╪════════╪═══════╪══════════╪════╪══════════════╪═══════════════╪═══════════╪═══════════╣
║account │0.0.1   │obaas  │100m      │8080│false         │1              │admin      │SPRING_BOOT║
╚════════╧════════╧═══════╧══════════╧════╧══════════════╧═══════════════╧═══════════╧═══════════╝
```

### workload update

```bash
oractl:>help workload update
NAME
       workload update - Update a specific workload for a given namespace.

SYNOPSIS
       workload update [--namespace String] [--id String] --profile String [--imageVersion String] --cpuRequest String --port Integer --addHealthProbe Boolean --liquibaseDB String --initialReplicas Integer --help 

OPTIONS
       --namespace String
       The namespace to create the workload in.
       [Mandatory]

       --id String
       The id of the workload.
       [Mandatory]

       --profile String
       The workload profile.
       [Optional]

       --imageVersion String
       The workload image version.
       [Mandatory]

       --cpuRequest String
       The workload cpu request.
       [Optional]

       --port Integer
       Port workload listens on.
       [Optional]

       --addHealthProbe Boolean
       The workload cpu request.
       [Optional]

       --liquibaseDB String
       The workload liquibase database.
       [Optional]

       --initialReplicas Integer
       Initial workload replicas.
       [Optional]

       --framework String
       The workload framework. Must be SPRING_BOOT or HELIDON
       [Mandatory]

       --help or -h 
       help for workload update
       [Optional]
```

For example:

```bash
oractl:>workload update --namespace myapp --id account --imageVersion 1.1.0 --addHealthProbe true --framework SPRING_BOOT
obaas-cli [workload update]: Workload [account] was successfully updated.
```

### workload getImage

```bash
oractl:>help workload getImage
NAME
       workload getImage - Get the image for a specific workload in a given namespace.

SYNOPSIS
       workload getImage [--namespace String] [--id String] --help 

OPTIONS
       --namespace String
       The namespace to query the workload from.
       [Mandatory]

       --id String
       The workload id.
       [Mandatory]

       --help or -h 
       help for workload getImage
       [Optional]
```

For example:

```bash
oractl:>workload getImage --namespace myapp --id account
╔═════╤══════════════════════════════════════════════╤═════════════════════════════════════╤════════╤═════════╤═════════════════════════════╤═══════╗
║Image│Image Name                                    │Base Image                           │Workload│Namespace│Created                      │Status ║
║ID   │                                              │                                     │        │         │                             │       ║
╠═════╪══════════════════════════════════════════════╪═════════════════════════════════════╪════════╪═════════╪═════════════════════════════╪═══════╣
║14   │iad.ocir.io/maacloud/calf/myapp-account:1.1.0 │ghcr.io/oracle/openjdk-image-obaas:21│account │myapp    │2024-12-13T16:07:40.529+00:00│CREATED║
╚═════╧══════════════════════════════════════════════╧═════════════════════════════════════╧════════╧═════════╧═════════════════════════════╧═══════╝
```

### workload delete

```bash
oractl:>help workload delete
NAME
       workload delete - Delete a specific workload for a given namespace.

SYNOPSIS
       workload delete [--namespace String] [--id String] --help 

OPTIONS
       --namespace String
       The namespace to delete the workload from.
       [Mandatory]

       --id String
       The workload id.
       [Mandatory]

       --help or -h 
       help for workload delete
       [Optional]
```

For example:

```bash
oractl:>workload delete --namespace myapp --id account
obaas-cli [workload delete]: Workload [account] was successfully deleted.
```

## Server Version

```bash
oractl:>help serverversion
NAME
       serverversion - Get obaas admin server version.

SYNOPSIS
       serverversion --help 

OPTIONS
       --help or -h 
       help for serverversion
       [Optional]

```

For example:

```bash
oractl:>serverversion
╔═══════╗
║Version║
╠═══════╣
║1.4.0  ║
╚═══════╝
```

## Logging

The log file for `oractl` on Mac or Unix machine is stored in the `$HOME/config/oractl` directory. The file name is `oractl-cli-history.log`
