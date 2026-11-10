# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

locals {
  group_label_prefix = var.group_label_prefix == null ? var.label_prefix : var.group_label_prefix
  plan_types         = { for plan_type in var.plan_types : lower(plan_type) => plan_type }
  backup_buckets = {
    (var.region_0) = oci_objectstorage_bucket.fsdr_backup_primary.name
    (var.region_1) = oci_objectstorage_bucket.fsdr_backup_standby.name
  }
  group_summaries = { for region, discovery in {
    (var.region_0) = data.oci_disaster_recovery_dr_protection_groups.region_0.dr_protection_group_collection
    (var.region_1) = data.oci_disaster_recovery_dr_protection_groups.region_1.dr_protection_group_collection
    } : region => try(one([
      for group in discovery[0].items : group if contains(["ACTIVE", "INACTIVE"], group.state)
  ]), null) }
  groups = {
    (var.region_0) = one(data.oci_disaster_recovery_dr_protection_group.region_0[*])
    (var.region_1) = one(data.oci_disaster_recovery_dr_protection_group.region_1[*])
  }
  # Preserve OCI's live peer association and role after recovery operations.
  associations = {
    for region, group in local.groups : region => try(
      contains(["PRIMARY", "STANDBY"], group.role) &&
      trimspace(group.peer_id) != "" &&
      trimspace(group.peer_region) != "" ? {
        role        = group.role
        peer_id     = group.peer_id
        peer_region = group.peer_region
      } : null,
      null
    )
  }
  protection_group_ids = {
    (var.region_0) = module.fsdr_region_0.dr_protection_group_id
    (var.region_1) = module.fsdr_region_1.dr_protection_group_id
  }
  roles = {
    (var.region_0) = try(local.groups[var.region_0].role, "PRIMARY")
    (var.region_1) = try(local.groups[var.region_1].role, "STANDBY")
  }
  storage_members = { for region, group in local.groups : region => [
    for member in try(group.members, []) : {
      member_id                       = member.member_id
      member_type                     = member.member_type
      destination_availability_domain = member.destination_availability_domain
      destination_backup_policy_id    = member.destination_backup_policy_id
      destination_compartment_id      = member.destination_compartment_id
      destination_snapshot_policy_id  = member.destination_snapshot_policy_id
      common_destination_key          = one(member.common_destination_key)
      destination_encryption_key      = one(member.destination_encryption_key)
      export_mappings                 = member.export_mappings
      source_volume_to_destination_encryption_key_mappings = [for mapping in member.source_volume_to_destination_encryption_key_mappings : {
        source_volume_id           = mapping.source_volume_id
        destination_encryption_key = one(mapping.destination_encryption_key)
      }]
    }
    if contains(["VOLUME_GROUP", "FILE_SYSTEM"], member.member_type)
  ] }
  bootstrap_storage_group_ids = [for member in module.storage.members : member.member_id]
  storage_recovered = anytrue([
    for member in concat(local.storage_members[var.region_0], local.storage_members[var.region_1]) :
    !contains(local.bootstrap_storage_group_ids, member.member_id) if member.member_type == "VOLUME_GROUP"
  ])
  members = { for region, cluster in var.clusters : region => concat([
    {
      member_id                                      = cluster.database_id
      member_type                                    = "AUTONOMOUS_DATABASE"
      autonomous_database_standby_type_for_dr_drills = var.adb_drill_standby_type
    },
    {
      member_id       = cluster.cluster_id
      member_type     = "OKE_CLUSTER"
      peer_cluster_id = var.clusters[region == var.region_0 ? var.region_1 : var.region_0].cluster_id
      backup_location = { bucket = local.backup_buckets[region], namespace = var.objectstorage_namespace }
      backup_config = local.roles[region] == "PRIMARY" ? {
        namespaces                     = concat(var.namespaces, ["obaas-system"])
        backup_schedule                = var.backup_schedule
        replicate_images               = "ENABLE"
        max_number_of_backups_retained = var.backup_retention
      } : null
      managed_node_pool_configs = [for kind, id in cluster.node_pools : {
        id = id, minimum = var.standby_node_counts[kind], maximum = var.node_counts[kind]
      }]
      load_balancer_mappings = local.roles[region] == "PRIMARY" ? [{
        source_load_balancer_id      = cluster.lb_id
        destination_load_balancer_id = var.clusters[region == var.region_0 ? var.region_1 : var.region_0].lb_id
      }] : []
    }
    ],
    # Existing membership contains the storage IDs activated by FSDR.
    [for member in module.storage.members : member if !local.storage_recovered && local.groups[var.region_0] == null && region == var.region_0],
    local.storage_members[region]
  ) }
  plans = { for region in [var.region_0, var.region_1] : region => {
    for key, plan_type in local.plan_types : key => {
      display_name    = format("%s-%s-%s", var.label_prefix, key, region)
      type            = plan_type
      refresh_trigger = var.plan_refresh_trigger
      verify_trigger  = var.plan_verify_trigger
      timeouts_create = var.timeouts.create
      timeouts_update = var.timeouts.update
      timeouts_delete = var.timeouts.delete
      } if !var.init_destroy && local.roles[region] == "STANDBY" && (
      plan_type != "STOP_DRILL" || try(local.groups[region].state == "INACTIVE" && local.groups[region].lifecycle_sub_state == "DR_DRILL_IN_PROGRESS", false)
    )
  } }
  automatic_dr = { for region, cluster in var.clusters : region => var.init_destroy || var.automatic_dr == null || local.roles[region] != "STANDBY" ? null : {
    display_name = format("%s-automatic-%s", var.label_prefix, region)
    members = [{
      member_id                  = cluster.database_id
      member_type                = "AUTONOMOUS_DATABASE"
      is_auto_switchover_enabled = var.automatic_dr.is_auto_switchover_enabled
      is_auto_failover_enabled   = var.automatic_dr.is_auto_failover_enabled
    }]
  } }
}
