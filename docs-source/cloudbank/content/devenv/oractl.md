+++
archetype = "page"
title = "Install CLI"
weight = 5
+++

The Oracle Backend for Microservices and AI CLI (*oractl*) is used to configure your backend and to deploy your Spring Boot applications to the backend.

1. Download the Oracle Backend for Microservices and AI CLI

   Download the CLI from [here](https://github.com/oracle/microservices-backend/releases/tag/OBAAS-1.3.0)

2. Install the Oracle Backend for Microservices and AI CLI

   To install the CLI, you just need to make sure it is executable and add it to your PATH environment variable.

    ```shell
    
    chmod +x oractl
    export PATH=/path/to/oractl:$PATH
    ```

    **NOTE:** If environment is a Mac you need run the following command `sudo xattr -r -d com.apple.quarantine <downloaded-file>` otherwise will you get a security warning and the CLI will not work.

3. Verify the installation

   Verify the CLI is installed using this command:

      ```shell
         $ oractl version
       _   _           __    _    ___
      / \ |_)  _.  _. (_    /  |   |
      \_/ |_) (_| (_| __)   \_ |_ _|_
      ===================================================================
      Application Name: Oracle Backend Platform :: Command Line Interface
      Application Version: (1.3.0)
      :: Spring Boot (v3.3.3) ::

      Ask for help:
         - Slack: https://oracledevs.slack.com/archives/C06L9CDGR6Z
         - email: obaas_ww@oracle.com

      Build Version: 1.3.0
      ```
