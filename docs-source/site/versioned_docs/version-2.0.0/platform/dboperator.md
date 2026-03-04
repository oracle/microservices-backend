---
title: Oracle Database Operator for Kubernetes
sidebar_position: 6
---
## Oracle Database Operator for Kubernetes

The Oracle Database Operator for Kubernetes (_OraOperator_, or simply the _operator_) extends the Kubernetes API with custom resources and controllers to automate Oracle Database lifecycle management.

[Full Documentation](https://github.com/oracle/oracle-database-operator).

Learn about using the OraOperator in the Livelab [Microservices and Kubernetes for an Oracle DBA](https://apexapps.oracle.com/pls/apex/dbpm/r/livelabs/view-workshop?wid=3734)

### Installing the Oracle Database Operator for Kubernetes

Oracle Database Operator for Kubernetes will be installed if the `oracle-database-operator.enabled` is set to `true` in the `values.yaml` file. The default namespace for Oracle Database Operator is `oracle-database-operator-system`.
