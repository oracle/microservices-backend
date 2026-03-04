# Simplify Microservices Architecture with Oracle AI Database

This repository contains sample code for simplifying microservices architectures by building solution examples for data-driven microservices that walk you through the creation of an open platform technology stack with the converged [Oracle Autonomous AI Database][ATP] including relational, JSON, text, spatial and graph data and using polyglot languages including Java and the Helidon MP and SE frameworks, Python and JavaScript via Node.js

Microservices are loosely-coupled service-oriented architectures with a bounded context. Microservices are increasingly used for application modernization to deliver agile application development practices. However, the data-driven nature of enterprise applications has made building, deploying, and maintaining microservices complex.

[Read our blogs](https://oracle.github.io/microservices-backend/spring/blogs)

## Projects

* [Oracle Backend for Microservices and AI](#oracle-backend-for-microservices-and-ai)
* [CloudBank AI](#cloudbank-ai)
* [Oracle Spring Boot Starters](#oracle-spring-boot-starters)
* [Data Refactoring Advisor](#data-refactoring-advisor)
* [Transactional Event Queues](#transactional-event-queues)

----
### Oracle Backend for Microservices and AI

The Oracle Backend for Microservices and AI (OBaaS) is a comprehensive microservices platform for AI microservices with Oracle AI Database.
[Documentation](https://oracle.github.io/microservices-backend/obaas/) 

Deploy into Oracle Cloud Infrastructure using Infrastructure as Code:

[![Deploy to Oracle Cloud][magic_button]][magic_arch_stack]

### CloudBank AI

Build an Application with Spring Boot and Spring Cloud Oracle with Oracle AI Database and Kubernetes.
* [Documentation](https://oracle.github.io/microservices-backend/cloudbank/)

### Oracle Spring Boot Starters

Spring Boot Starters that make it easy to use various Oracle technologies in Spring Boot projects.
* [Documentation](https://oracle.github.io/microservices-backend/spring/starters/)

### Data Refactoring Advisor

Data Refactoring Advisor is an innovative methodology designed to assist existing Oracle Database users in refactoring their schemas and identifying communities based on join activity.
* [Documentation](./data-refactoring-advisor/README.md)

### Transactional Event Queues

* [Sample Code](./code-teq)


## Contributing

This project welcomes contributions from the community. Before submitting a pull request, please [review our contribution guide](./CONTRIBUTING.md)

## Security

Please consult the [security guide](./SECURITY.md) for our responsible security vulnerability disclosure process

## License

Copyright (c) 2021, 2026, Oracle and/or its affiliates.

Licensed under the Universal Permissive License v 1.0 as shown at <https://oss.oracle.com/licenses/upl>.

[ATP]: https://docs.oracle.com/en/cloud/paas/autonomous-database/index.html
[magic_button]: https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg
[magic_arch_stack]: https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/oracle/microservices-backend/releases/latest/download/obaas-iac.zip