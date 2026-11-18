# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  # Claim prefixes follow the obaas release's StatefulSets and operator resources.
  requirements = merge({
    etcd       = { prefix = "data-obaas-etcd", replicas = 3, size_in_gbs = 8, placement = 0 }
    zookeeper  = { prefix = "data-obaas-zookeeper", replicas = 1, size_in_gbs = 8, placement = 3 }
    signoz     = { prefix = "signoz-db-obaas-signoz", replicas = 1, size_in_gbs = 1, placement = 4 }
    clickhouse = { prefix = "data-volumeclaim-template-chi-obaas-clickhouse-cluster-0-0", replicas = 1, size_in_gbs = 20, placement = 5 }
    }, var.deploy_kafka ? {
    kafka = { prefix = "data-0-obaas-kafka-cluster-dual-role", replicas = 3, size_in_gbs = 100, placement = 6 }
  } : {})
  claims = merge([for component, requirement in local.requirements : {
    for replica in range(requirement.replicas) : format("%s-%s", component, replica) => {
      claim_name          = format("%s-%s", requirement.prefix, replica)
      size_in_gbs         = max(50, requirement.size_in_gbs)
      availability_domain = var.source_availability_domains[(requirement.placement + replica) % length(var.source_availability_domains)]
    }
  }]...)
  chart_storage = { for component, requirement in local.requirements : component => {
    replicas      = requirement.replicas
    size_in_gbs   = requirement.size_in_gbs
    storage_class = "obaas-preallocated"
  } }
}
