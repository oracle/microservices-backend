+++
archetype = "page"
title = "Install IDE Plugin"
weight = 10
+++

Some modules contain optional parts which show you how to do deployments and configuration with the IDE plugins instead of using the CLI.  If you plan to do those optional parts, you need to install the VS Code extension for Oracle Backend for Microservices and AI. It is an extension to browse and deploy applications on the Oracle Backend for Microservices and AI platform. This plugin allows to inspect the content of an Oracle Backend for Microservices and AI deployment, in terms of applications, services and related configurations.

1. Download the plug-in from [here](https://github.com/oracle/microservices-backend/releases/tag/OBAAS-1.3.0).

2. On the VS Code right menu bar, click on **Extensions** item:

    ![Extensions list](../images/extensions.png " ")

3. From the up-right corner menu, choose **Install from VSIX...**:

    ![Install](../images/install.png " ")

   and upload plug-in binaries previously downloaded.

4. Re-start VS Code to make fully operative the plugin, in command palette execute a window reload:

   ![VSReload](../images/reloadWindow.png " ")

5. If you don't see the plugin in the left bar, with the Oracle logo, as shown here:

    ![Additional](../images/additional.png " ")

   click on **Additional Views** menu to select the **Oracle Backend for Microservices and AI**.
