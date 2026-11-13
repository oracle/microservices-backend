# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at https://oss.oracle.com/licenses/upl

# OCI mock overrides require complete nested objects.
mock_provider "oci" {
  mock_data "oci_disaster_recovery_dr_protection_groups" {
    defaults = { dr_protection_group_collection = [{ items = [{
      association          = []
      compartment_id       = ""
      defined_tags         = {}
      disassociate_trigger = 0
      display_name         = ""
      freeform_tags        = {}
      life_cycle_details   = ""
      lifecycle_sub_state  = ""
      log_location         = []
      members              = []
      peer_id              = ""
      peer_region          = ""
      role                 = ""
      state                = "ACTIVE"
      system_tags          = {}
      time_created         = ""
      time_updated         = ""
      id                   = "pg-0"
      }]
    }] }
  }
  mock_data "oci_disaster_recovery_dr_protection_group" {
    defaults = { role = "PRIMARY", members = [] }
  }
  mock_data "oci_disaster_recovery_dr_plan_executions" {
    defaults = { dr_plan_execution_collection = [{ items = [] }] }
  }
  mock_resource "oci_objectstorage_bucket" {
    defaults = { defined_tags = { "Oracle-Tags.CreatedBy" = "test-user" } }
  }
}
mock_provider "oci" {
  alias = "fsdr_region_1"
  mock_data "oci_disaster_recovery_dr_protection_groups" {
    defaults = { dr_protection_group_collection = [{ items = [{
      association          = []
      compartment_id       = ""
      defined_tags         = {}
      disassociate_trigger = 0
      display_name         = ""
      freeform_tags        = {}
      life_cycle_details   = ""
      lifecycle_sub_state  = ""
      log_location         = []
      members              = []
      peer_id              = ""
      peer_region          = ""
      role                 = ""
      state                = "ACTIVE"
      system_tags          = {}
      time_created         = ""
      time_updated         = ""
      id                   = "pg-1"
      }]
    }] }
  }
  mock_data "oci_disaster_recovery_dr_protection_group" {
    defaults = { role = "STANDBY", members = [] }
  }
  mock_data "oci_disaster_recovery_dr_plan_executions" {
    defaults = { dr_plan_execution_collection = [{ items = [] }] }
  }
}
mock_provider "oci" { alias = "home_region" }

override_module {
  target = module.storage
  outputs = {
    members = [{ member_id = "original-group"
      member_type                = "VOLUME_GROUP"
      destination_compartment_id = "test-compartment"
    }]
  }
}

variables {
  tenancy_id                      = "test-tenancy"
  compartment_id                  = "test-compartment"
  label_prefix                    = "storagetest"
  region_0                        = "uk-london-1"
  region_1                        = "uk-cardiff-1"
  objectstorage_namespace         = "test-namespace"
  destination_availability_domain = "TEST:CWL-AD-1"
  volumes                         = { etcd = { id = "original-volume", availability_domain = "TEST:LHR-AD-1" } }
  node_counts                     = { cpu = 3, gpu = 0 }
  standby_node_counts             = { cpu = 1, gpu = 0 }
  clusters = {
    uk-london-1  = { cluster_id = "cluster-0", database_id = "adb-0", workers_group = "workers-0", node_pools = { cpu = "pool-0" }, lb_id = "lb-0", configuration_ready_id = "ready-0" }
    uk-cardiff-1 = { cluster_id = "cluster-1", database_id = "adb-1", workers_group = "workers-1", node_pools = { cpu = "pool-1" }, lb_id = "lb-1", configuration_ready_id = "ready-1" }
  }
}

run "cleanup_from_empty_state" {
  command = plan
  variables {
    init_destroy = true
  }
  override_data {
    target = data.oci_disaster_recovery_dr_protection_groups.region_0
    values = { dr_protection_group_collection = [{ items = [] }] }
  }
  override_data {
    target = data.oci_disaster_recovery_dr_protection_groups.region_1
    values = { dr_protection_group_collection = [{ items = [] }] }
  }
  expect_failures = [terraform_data.init_destroy_validation[0]]
}

run "cleanup_paired_groups" {
  command = plan
  variables {
    init_destroy = true
  }
  override_data {
    target = data.oci_disaster_recovery_dr_protection_group.region_0
    values = { role = "PRIMARY", peer_id = "pg-1", peer_region = "uk-cardiff-1", members = [] }
  }
  override_data {
    target = data.oci_disaster_recovery_dr_protection_group.region_1
    values = { role = "STANDBY", peer_id = "pg-0", peer_region = "uk-london-1", members = [] }
  }
  override_data {
    target = data.oci_disaster_recovery_dr_protection_group.prepared_region_0
    values = { role = "UNCONFIGURED" }
  }
  override_data {
    target = data.oci_disaster_recovery_dr_protection_group.prepared_region_1
    values = { role = "UNCONFIGURED" }
  }
  assert {
    condition     = length(output.regions.region_0.dr_protection_group.members) == 0 && length(output.regions.region_1.dr_protection_group.members) == 0 && length(output.plan_ids) == 0
    error_message = "Cleanup must clear both memberships and remove recovery plans."
  }
}

run "bootstrap" {
  command = plan
  override_data {
    target = data.oci_disaster_recovery_dr_protection_groups.region_0
    values = { dr_protection_group_collection = [{ items = [] }] }
  }
  override_data {
    target = data.oci_disaster_recovery_dr_protection_groups.region_1
    values = { dr_protection_group_collection = [{ items = [] }] }
  }
  assert {
    condition     = [for member in output.regions.region_0.dr_protection_group.members : member.member_id if member.member_type == "VOLUME_GROUP"] == ["original-group"] && !output.storage_recovered
    error_message = "Bootstrap must enroll the original groups and render their reserved PVs."
  }
  assert {
    condition     = length(one([for member in output.regions.region_0.dr_protection_group.members : member if member.member_type == "OKE_CLUSTER"]).load_balancer_mappings) == 1 && length(one([for member in output.regions.region_1.dr_protection_group.members : member if member.member_type == "OKE_CLUSTER"]).load_balancer_mappings) == 0
    error_message = "Only the primary OKE member may configure load-balancer recovery mappings."
  }
  assert {
    condition     = one(one([for member in output.regions.region_0.dr_protection_group.members : member if member.member_type == "OKE_CLUSTER"]).backup_location).bucket == "storagetest-backup-uk-cardiff-1" && one(one([for member in output.regions.region_1.dr_protection_group.members : member if member.member_type == "OKE_CLUSTER"]).backup_location).bucket == "storagetest-backup-uk-london-1"
    error_message = "Each OKE member must use the peer-region backup bucket."
  }
  assert {
    condition     = length(one(one([for member in output.regions.region_0.dr_protection_group.members : member if member.member_type == "OKE_CLUSTER"]).backup_config).namespaces) == 0 && length(one(one([for member in output.regions.region_0.dr_protection_group.members : member if member.member_type == "OKE_CLUSTER"]).backup_config).exclude_namespaces) == 0
    error_message = "OKE backups must use OCI's all-namespaces default."
  }
}

run "initial_primary" {
  command = plan
  override_data {
    target = data.oci_disaster_recovery_dr_protection_group.region_0
    values = {
      role = "PRIMARY"
      members = [{
        autonomous_database_standby_type_for_dr_drills       = ""
        backend_set_mappings                                 = []
        backup_config                                        = []
        backup_location                                      = []
        block_volume_attach_and_mount_operations             = []
        block_volume_operations                              = []
        bucket                                               = ""
        common_destination_key                               = []
        connection_string_type                               = ""
        db_system_admin_user_details                         = []
        db_system_replication_user_details                   = []
        destination_availability_domain                      = ""
        destination_backup_policy_id                         = ""
        destination_capacity_reservation_id                  = ""
        destination_dedicated_vm_host_id                     = ""
        destination_encryption_key                           = []
        destination_load_balancer_id                         = ""
        destination_network_load_balancer_id                 = ""
        destination_snapshot_policy_id                       = ""
        dr_drill_properties                                  = []
        export_mappings                                      = []
        file_system_operations                               = []
        gtid_reconciliation_timeout                          = 0
        is_continue_on_gtid_reconciliation_timeout           = false
        is_movable                                           = false
        is_retain_fault_domain                               = false
        is_start_stop_enabled                                = false
        jump_host_id                                         = ""
        load_balancer_mappings                               = []
        managed_node_pool_configs                            = []
        namespace                                            = ""
        network_load_balancer_mappings                       = []
        password_vault_secret_id                             = ""
        peer_cluster_id                                      = ""
        peer_db_system_id                                    = ""
        resource_modifier_mappings                           = []
        source_volume_to_destination_encryption_key_mappings = []
        vault_mappings                                       = []
        virtual_node_pool_configs                            = []
        vnic_mapping                                         = []
        vnic_mappings                                        = []
        member_id                                            = "original-group"
        member_type                                          = "VOLUME_GROUP"
        destination_compartment_id                           = "test-compartment"
      }]
    }
  }
  assert {
    condition     = [for member in output.regions.region_0.dr_protection_group.members : member.member_id if member.member_type == "VOLUME_GROUP"] == ["original-group"] && !output.storage_recovered
    error_message = "The original primary must retain its enrolled groups and PV management."
  }
}

run "active_drill" {
  command = plan
  variables {
    plan_types = ["START_DRILL", "STOP_DRILL"]
  }
  override_data {
    target = data.oci_disaster_recovery_dr_protection_group.region_1
    values = { role = "STANDBY", state = "INACTIVE", lifecycle_sub_state = "DR_DRILL_IN_PROGRESS", members = [] }
  }
  assert {
    condition     = toset(keys(output.regions.region_1.dr_plans)) == toset(["start_drill", "stop_drill"])
    error_message = "An active drill must expose its stop-drill plan in the standby region."
  }
}

run "switchover" {
  command = plan
  override_data {
    target = data.oci_disaster_recovery_dr_protection_group.region_0
    values = { role = "STANDBY", members = [] }
  }
  override_data {
    target = data.oci_disaster_recovery_dr_protection_group.region_1
    values = {
      role = "PRIMARY"
      members = [{
        autonomous_database_standby_type_for_dr_drills       = ""
        backend_set_mappings                                 = []
        backup_config                                        = []
        backup_location                                      = []
        block_volume_attach_and_mount_operations             = []
        block_volume_operations                              = []
        bucket                                               = ""
        common_destination_key                               = []
        connection_string_type                               = ""
        db_system_admin_user_details                         = []
        db_system_replication_user_details                   = []
        destination_availability_domain                      = ""
        destination_backup_policy_id                         = ""
        destination_capacity_reservation_id                  = ""
        destination_dedicated_vm_host_id                     = ""
        destination_encryption_key                           = []
        destination_load_balancer_id                         = ""
        destination_network_load_balancer_id                 = ""
        destination_snapshot_policy_id                       = ""
        dr_drill_properties                                  = []
        export_mappings                                      = []
        file_system_operations                               = []
        gtid_reconciliation_timeout                          = 0
        is_continue_on_gtid_reconciliation_timeout           = false
        is_movable                                           = false
        is_retain_fault_domain                               = false
        is_start_stop_enabled                                = false
        jump_host_id                                         = ""
        load_balancer_mappings                               = []
        managed_node_pool_configs                            = []
        namespace                                            = ""
        network_load_balancer_mappings                       = []
        password_vault_secret_id                             = ""
        peer_cluster_id                                      = ""
        peer_db_system_id                                    = ""
        resource_modifier_mappings                           = []
        source_volume_to_destination_encryption_key_mappings = []
        vault_mappings                                       = []
        virtual_node_pool_configs                            = []
        vnic_mapping                                         = []
        vnic_mappings                                        = []
        member_id                                            = "activated-group-1"
        member_type                                          = "VOLUME_GROUP"
        destination_compartment_id                           = "test-compartment"
      }]
    }
  }
  assert {
    condition     = length([for member in output.regions.region_0.dr_protection_group.members : member if member.member_type == "VOLUME_GROUP"]) == 0 && [for member in output.regions.region_1.dr_protection_group.members : member.member_id if member.member_type == "VOLUME_GROUP"] == ["activated-group-1"] && output.storage_recovered
    error_message = "Switchover must preserve the activated groups and native PV ownership."
  }
  assert {
    condition     = one(one([for member in output.regions.region_1.dr_protection_group.members : member if member.member_type == "OKE_CLUSTER"]).backup_location).bucket == "storagetest-backup-uk-london-1" && length(one([for member in output.regions.region_1.dr_protection_group.members : member if member.member_type == "OKE_CLUSTER"]).backup_config) == 1
    error_message = "The new primary must back up to the new standby region."
  }
}

run "switchback" {
  command = plan
  override_data {
    target = data.oci_disaster_recovery_dr_protection_group.region_0
    values = {
      role = "PRIMARY"
      members = [
        {
          autonomous_database_standby_type_for_dr_drills       = ""
          backend_set_mappings                                 = []
          backup_config                                        = []
          backup_location                                      = []
          block_volume_attach_and_mount_operations             = []
          block_volume_operations                              = []
          bucket                                               = ""
          connection_string_type                               = ""
          db_system_admin_user_details                         = []
          db_system_replication_user_details                   = []
          destination_availability_domain                      = ""
          destination_backup_policy_id                         = ""
          destination_capacity_reservation_id                  = ""
          destination_dedicated_vm_host_id                     = ""
          destination_encryption_key                           = []
          destination_load_balancer_id                         = ""
          destination_network_load_balancer_id                 = ""
          destination_snapshot_policy_id                       = ""
          dr_drill_properties                                  = []
          export_mappings                                      = []
          file_system_operations                               = []
          gtid_reconciliation_timeout                          = 0
          is_continue_on_gtid_reconciliation_timeout           = false
          is_movable                                           = false
          is_retain_fault_domain                               = false
          is_start_stop_enabled                                = false
          jump_host_id                                         = ""
          load_balancer_mappings                               = []
          managed_node_pool_configs                            = []
          namespace                                            = ""
          network_load_balancer_mappings                       = []
          password_vault_secret_id                             = ""
          peer_cluster_id                                      = ""
          peer_db_system_id                                    = ""
          resource_modifier_mappings                           = []
          source_volume_to_destination_encryption_key_mappings = []
          vault_mappings                                       = []
          virtual_node_pool_configs                            = []
          vnic_mapping                                         = []
          vnic_mappings                                        = []

          member_id                  = "activated-group-0"
          member_type                = "VOLUME_GROUP"
          destination_compartment_id = "test-compartment"
          common_destination_key     = [{ encryption_key_id = "volume-key", vault_id = "volume-vault" }]
        },
        {
          autonomous_database_standby_type_for_dr_drills       = ""
          backend_set_mappings                                 = []
          backup_config                                        = []
          backup_location                                      = []
          block_volume_attach_and_mount_operations             = []
          block_volume_operations                              = []
          bucket                                               = ""
          common_destination_key                               = []
          connection_string_type                               = ""
          db_system_admin_user_details                         = []
          db_system_replication_user_details                   = []
          destination_availability_domain                      = ""
          destination_backup_policy_id                         = ""
          destination_capacity_reservation_id                  = ""
          destination_compartment_id                           = ""
          destination_dedicated_vm_host_id                     = ""
          destination_load_balancer_id                         = ""
          destination_network_load_balancer_id                 = ""
          file_system_operations                               = []
          gtid_reconciliation_timeout                          = 0
          is_continue_on_gtid_reconciliation_timeout           = false
          is_movable                                           = false
          is_retain_fault_domain                               = false
          is_start_stop_enabled                                = false
          jump_host_id                                         = ""
          load_balancer_mappings                               = []
          managed_node_pool_configs                            = []
          namespace                                            = ""
          network_load_balancer_mappings                       = []
          password_vault_secret_id                             = ""
          peer_cluster_id                                      = ""
          peer_db_system_id                                    = ""
          resource_modifier_mappings                           = []
          source_volume_to_destination_encryption_key_mappings = []
          vault_mappings                                       = []
          virtual_node_pool_configs                            = []
          vnic_mapping                                         = []
          vnic_mappings                                        = []

          member_id                      = "recovered-filesystem"
          member_type                    = "FILE_SYSTEM"
          destination_snapshot_policy_id = "snapshot-policy"
          dr_drill_properties            = []
          destination_encryption_key     = [{ encryption_key_id = "fs-key", vault_id = "fs-vault" }]
          export_mappings                = [{ export_id = "fs-export", destination_mount_target_id = "fs-mount" }]
        }
      ]
    }
  }
  override_data {
    target = data.oci_disaster_recovery_dr_protection_group.region_1
    values = { role = "STANDBY", members = [] }
  }
  assert {
    condition     = toset([for member in output.regions.region_0.dr_protection_group.members : member.member_id if contains(["VOLUME_GROUP", "FILE_SYSTEM"], member.member_type)]) == toset(["activated-group-0", "recovered-filesystem"]) && length([for member in output.regions.region_1.dr_protection_group.members : member if contains(["VOLUME_GROUP", "FILE_SYSTEM"], member.member_type)]) == 0 && output.storage_recovered
    error_message = "Switchback must retain recovered storage and PV ownership when region 0 is primary again."
  }
  assert {
    condition     = one(one([for member in output.regions.region_0.dr_protection_group.members : member if member.member_type == "VOLUME_GROUP"]).common_destination_key).encryption_key_id == "volume-key" && one(one([for member in output.regions.region_0.dr_protection_group.members : member if member.member_type == "FILE_SYSTEM"]).destination_encryption_key).encryption_key_id == "fs-key"
    error_message = "Preserved storage members must retain their recovery encryption settings."
  }
}

run "missing_initial_group_after_recovery" {
  command = plan
  override_data {
    target = data.oci_disaster_recovery_dr_protection_groups.region_0
    values = { dr_protection_group_collection = [{ items = [] }] }
  }
  override_data {
    target = data.oci_disaster_recovery_dr_protection_group.region_1
    values = {
      role = "PRIMARY"
      members = [{
        autonomous_database_standby_type_for_dr_drills       = ""
        backend_set_mappings                                 = []
        backup_config                                        = []
        backup_location                                      = []
        block_volume_attach_and_mount_operations             = []
        block_volume_operations                              = []
        bucket                                               = ""
        common_destination_key                               = []
        connection_string_type                               = ""
        db_system_admin_user_details                         = []
        db_system_replication_user_details                   = []
        destination_availability_domain                      = ""
        destination_backup_policy_id                         = ""
        destination_capacity_reservation_id                  = ""
        destination_dedicated_vm_host_id                     = ""
        destination_encryption_key                           = []
        destination_load_balancer_id                         = ""
        destination_network_load_balancer_id                 = ""
        destination_snapshot_policy_id                       = ""
        dr_drill_properties                                  = []
        export_mappings                                      = []
        file_system_operations                               = []
        gtid_reconciliation_timeout                          = 0
        is_continue_on_gtid_reconciliation_timeout           = false
        is_movable                                           = false
        is_retain_fault_domain                               = false
        is_start_stop_enabled                                = false
        jump_host_id                                         = ""
        load_balancer_mappings                               = []
        managed_node_pool_configs                            = []
        namespace                                            = ""
        network_load_balancer_mappings                       = []
        password_vault_secret_id                             = ""
        peer_cluster_id                                      = ""
        peer_db_system_id                                    = ""
        resource_modifier_mappings                           = []
        source_volume_to_destination_encryption_key_mappings = []
        vault_mappings                                       = []
        virtual_node_pool_configs                            = []
        vnic_mapping                                         = []
        vnic_mappings                                        = []
        member_id                                            = "activated-group-1"
        member_type                                          = "VOLUME_GROUP"
        destination_compartment_id                           = "test-compartment"
      }]
    }
  }
  assert {
    condition     = length([for member in output.regions.region_0.dr_protection_group.members : member if member.member_type == "VOLUME_GROUP"]) == 0 && [for member in output.regions.region_1.dr_protection_group.members : member.member_id if member.member_type == "VOLUME_GROUP"] == ["activated-group-1"] && output.storage_recovered
    error_message = "Switchover must preserve the activated groups and native PV ownership."
  }
}

