# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

resource "oci_identity_dynamic_group" "fsdr" {
  compartment_id = var.tenancy_id
  name           = format("%s-groups", var.label_prefix)
  description    = "OBaaS FSDR protection groups"
  # The log bucket and protection groups share the deployment principal's default tag.
  matching_rule = format("ALL {resource.type = 'drprotectiongroup', resource.compartment.id = '%s', tag.Oracle-Tags.CreatedBy.value = '%s'}", var.compartment_id, oci_objectstorage_bucket.fsdr_logs_region_0.defined_tags["Oracle-Tags.CreatedBy"])
  provider      = oci.home_region
}

resource "oci_identity_policy" "fsdr" {
  compartment_id = var.tenancy_id
  name           = format("%s-groups", var.label_prefix)
  description    = "OBaaS full-stack recovery"
  statements = concat([for family in ["disaster-recovery-family", "autonomous-database-family", "cluster-family", "instance-family", "compute-container-family", "object-family", "volume-family", "file-family", "virtual-network-family", "load-balancers", "repos"] :
    format("Allow dynamic-group %s to manage %s in compartment id %s", oci_identity_dynamic_group.fsdr.name, family, family == "autonomous-database-family" ? coalesce(var.adb_compartment_id, var.compartment_id) : var.compartment_id)
    ], [
    format("Allow dynamic-group %s to read objectstorage-namespaces in tenancy", oci_identity_dynamic_group.fsdr.name),
    format("Allow dynamic-group %s to read all-resources in compartment id %s", oci_identity_dynamic_group.fsdr.name, var.compartment_id),
    format("Allow dynamic-group %s to use instance-images in tenancy", oci_identity_dynamic_group.fsdr.name),
    format("Allow dynamic-group %s to use tag-namespaces in tenancy", oci_identity_dynamic_group.fsdr.name),
    format("Allow dynamic-group %s to read repos in tenancy", oci_identity_dynamic_group.fsdr.name)
    ], flatten([for cluster in values(var.clusters) : [for service_account in ["brie-creator", "brie-reader"] :
      format("Allow any-user to manage objects in compartment id %s where all {request.principal.type = 'workload', request.principal.namespace = 'brie', request.principal.service_account = '%s', request.principal.cluster_id = '%s'}", var.compartment_id, service_account, cluster.cluster_id)
      ]]), flatten([for cluster in values(var.clusters) : [for family in ["object-family", "cluster-family"] :
      format("Allow dynamic-group %s to manage %s in compartment id %s", cluster.workers_group, family, var.compartment_id)
    ]]), [for database_id, compartment_id in var.external_databases :
    format("Allow dynamic-group %s to manage autonomous-databases in compartment id %s where target.database.id = '%s'", oci_identity_dynamic_group.fsdr.name, compartment_id, database_id)
  ])
  provider = oci.home_region
}

resource "oci_identity_dynamic_group" "fsdr_container" {
  compartment_id = var.tenancy_id
  name           = format("%s-containers", var.label_prefix)
  description    = "FSDR runtime OKE container instances"
  matching_rule  = format("ALL {resource.type = 'computecontainerinstance', resource.compartment.id = '%s'}", var.compartment_id)
  provider       = oci.home_region
}

resource "oci_identity_policy" "fsdr_container" {
  compartment_id = var.tenancy_id
  name           = format("%s-containers", var.label_prefix)
  description    = "FSDR runtime OKE operations"
  statements = [for family in ["object-family", "cluster-family"] :
    format("Allow dynamic-group %s to manage %s in compartment id %s", oci_identity_dynamic_group.fsdr_container.name, family, var.compartment_id)
  ]
  provider = oci.home_region
}
