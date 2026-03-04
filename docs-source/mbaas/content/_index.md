
# Oracle Backend for Parse Platform - Developer Preview

&nbsp;
{{< hint type=[warning] icon=gdoc_fire title="Deprecation Notice" >}}
Oracle Database Storage Adapter for Parse has been upstreamed to the Parse community, and this Developer Preview is deprecated. You can see an example of how Parse Platform can be used to build backends with Oracle Database using the storage adapter [here](https://www.linkedin.com/pulse/developing-mobile-apps-oracle-free23c-doug-drechsel-9tc6e/).
{{< /hint >}}
&nbsp;

Oracle Backend for Parse Platform deploys mobile applications using Parse mobile APIs, and provisions an Oracle Backend as a Service (OBaaS)
with Oracle Database and other infrastructure components that operate on multiple clouds. This service vastly simplifies the task of building, testing,
and operating a mobile application development platform for reliable, secure, and scalable enterprise applications. This version includes an Oracle Database storage adapter
for Parse (Parse already has MongoDB and Postgres adapters), and a proof-of-concept for Google Firebase APIs emulated using Parse mobile APIs.

The Oracle Backend for Parse Platform is based on the [Parse Platform](https://parseplatform.org/).

In addition to an Oracle Autonomous Database Serverless instance, the following software components are deployed in an OCI Container
Engine for Kubernetes (OKE) for customer usage with Oracle Backend for Parse Platform:

* Parse Server, plus the Oracle Database storage adapter for Parse
* Parse Dashboard

&nbsp;
{{< hint type=[warning] icon=gdoc_fire title="Interested in Spring Boot or Microservices, too?" >}}
Check out [Oracle Backend for Spring Boot and Microservices](https://oracle.github.io/microservices-backend/spring/)
{{< /hint >}}
&nbsp;

## Developer Preview

This release is a *Developer Preview*. This means that not all functionality is complete. In this release, approximately 80-90% of the Parse mobile APIs are working. For
interested developers, approximately 2270 out of 2700 tests run successfully. This release is based on Parse Server version 5.2.7 and Parse Dashboard 5.0.0. Oracle is
releasing this as a *Developer Preview* to allow interested developers to try it and provide feedback.

The following application program interface (API) families are mostly working: 

* Database, including query
* Identity/Security
* File
* Caching
* GeoPoints
* Config
* Data

The following API families are not expected to work in this release:

* Cloud functions
* GraphQL
* Live query
* Push notifications

The exposed Parse mobile API is exactly the same as an upstream Parse Server version 5.2.7. There are no changes to the public-facing API.
All existing Parse Software Development Kits (SDKs) should work as-is with this *Developer Preview* for those APIs that are working.


## About the Oracle Database Storage Adapter for Parse

This *Developer Preview* includes an Oracle Database storage adapter for Parse based on Parse Server version 5.2.7. The storage
adapter is implemented using the [Node.js node-oracledb](https://oracle.github.io/node-oracledb/) library. Data is stored in the
database in JavaScript Object Notation (JSON) collections, using the [Simple Oracle Document Access (SODA)](https://docs.oracle.com/en/database/oracle/simple-oracle-document-access/)
API.

