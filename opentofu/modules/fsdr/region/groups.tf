# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

resource "oci_disaster_recovery_dr_protection_group" "dr_protection_group" {
  compartment_id = var.compartment_id
  defined_tags   = var.defined_tags
  display_name   = var.display_name
  freeform_tags  = var.freeform_tags
  log_location {
    bucket    = var.log_location["bucket"]
    namespace = var.log_location["namespace"]
  }
  # Preserve recovery roles and the provider's state-local, monotonic trigger.
  lifecycle {
    ignore_changes = [association, disassociate_trigger]
  }
  dynamic "association" {
    for_each = var.association == null ? [] : [1]
    content {
      role        = var.association["role"]
      peer_id     = var.association["peer_id"]
      peer_region = var.association["peer_region"]
    }
  }
  dynamic "members" {
    for_each = var.members
    content {
      autonomous_database_standby_type_for_dr_drills = members.value["autonomous_database_standby_type_for_dr_drills"]
      member_id                                      = members.value["member_id"]
      member_type                                    = members.value["member_type"]
      bucket                                         = members.value["bucket"]
      connection_string_type                         = members.value["connection_string_type"]
      destination_availability_domain                = members.value["destination_availability_domain"]
      destination_backup_policy_id                   = members.value["destination_backup_policy_id"]
      destination_capacity_reservation_id            = members.value["destination_capacity_reservation_id"]
      destination_compartment_id                     = members.value["destination_compartment_id"]
      destination_dedicated_vm_host_id               = members.value["destination_dedicated_vm_host_id"]
      destination_load_balancer_id                   = members.value["destination_load_balancer_id"]
      destination_network_load_balancer_id           = members.value["destination_network_load_balancer_id"]
      destination_snapshot_policy_id                 = members.value["destination_snapshot_policy_id"]
      gtid_reconciliation_timeout                    = members.value["gtid_reconciliation_timeout"]
      is_continue_on_gtid_reconciliation_timeout     = members.value["is_continue_on_gtid_reconciliation_timeout"]
      is_movable                                     = members.value["is_movable"]
      is_retain_fault_domain                         = members.value["is_retain_fault_domain"]
      is_start_stop_enabled                          = members.value["is_start_stop_enabled"]
      jump_host_id                                   = members.value["jump_host_id"]
      namespace                                      = members.value["namespace"]
      password_vault_secret_id                       = members.value["password_vault_secret_id"]
      peer_cluster_id                                = members.value["peer_cluster_id"]
      peer_db_system_id                              = members.value["peer_db_system_id"]

      dynamic "backend_set_mappings" {
        for_each = (members.value["member_type"] == "LOAD_BALANCER"
        || members.value["member_type"] == "NETWORK_LOAD_BALANCER") ? members.value["backend_set_mappings"] : []
        content {
          destination_backend_set_name   = backend_set_mappings.value["destination_backend_set_name"]
          is_backend_set_for_non_movable = backend_set_mappings.value["is_backend_set_for_non_movable"]
          source_backend_set_name        = backend_set_mappings.value["source_backend_set_name"]
        }
      }
      dynamic "backup_config" {
        for_each = members.value["member_type"] == "OKE_CLUSTER" && members.value["backup_config"] != null ? [1] : []
        content {
          backup_schedule                   = members.value["backup_config"]["backup_schedule"]
          exclude_namespaces                = members.value["backup_config"]["exclude_namespaces"]
          image_replication_vault_secret_id = members.value["backup_config"]["image_replication_vault_secret_id"]
          max_number_of_backups_retained    = members.value["backup_config"]["max_number_of_backups_retained"]
          namespaces                        = members.value["backup_config"]["namespaces"]
          replicate_images                  = members.value["backup_config"]["replicate_images"]
        }
      }
      dynamic "backup_location" {
        for_each = members.value["member_type"] == "OKE_CLUSTER" && members.value["backup_location"] != null ? [1] : []
        content {
          bucket    = members.value["backup_location"]["bucket"]
          namespace = members.value["backup_location"]["namespace"]
        }
      }
      dynamic "block_volume_attach_and_mount_operations" {
        for_each = (members.value["member_type"] == "COMPUTE_INSTANCE_NON_MOVABLE" &&
          (length(members.value["block_volume_attach_and_mount_operations"]["attachments"]) > 0
        || length(members.value["block_volume_attach_and_mount_operations"]["mounts"]) > 0)) ? [1] : []
        content {
          dynamic "attachments" {
            for_each = members.value["block_volume_attach_and_mount_operations"]["attachments"]
            content {
              block_volume_id                         = attachments.value["block_volume_id"]
              volume_attachment_reference_instance_id = attachments.value["volume_attachment_reference_instance_id"]
            }
          }
          dynamic "mounts" {
            for_each = members.value["block_volume_attach_and_mount_operations"]["mounts"]
            content {
              mount_point = mounts.value["mount_point"]
            }
          }
        }
      }
      dynamic "common_destination_key" {
        for_each = members.value["member_type"] == "VOLUME_GROUP" && members.value["common_destination_key"] != null ? [1] : []
        content {
          encryption_key_id = members.value["common_destination_key"]["encryption_key_id"]
          vault_id          = members.value["common_destination_key"]["vault_id"]
        }
      }
      dynamic "db_system_admin_user_details" {
        for_each = members.value["member_type"] == "MYSQL_DB_SYSTEM" && members.value["db_system_admin_user_details"] != null ? [1] : []
        content {
          password_vault_secret_id = members.value["db_system_admin_user_details"]["password_vault_secret_id"]
          username                 = members.value["db_system_admin_user_details"]["username"]
        }
      }
      dynamic "db_system_replication_user_details" {
        for_each = members.value["member_type"] == "MYSQL_DB_SYSTEM" && members.value["db_system_replication_user_details"] != null ? [1] : []
        content {
          password_vault_secret_id = members.value["db_system_replication_user_details"]["password_vault_secret_id"]
          username                 = members.value["db_system_replication_user_details"]["username"]
        }
      }
      dynamic "destination_encryption_key" {
        for_each = (members.value["member_type"] == "AUTONOMOUS_DATABASE" || members.value["member_type"] == "FILE_SYSTEM") && members.value["destination_encryption_key"] != null ? [1] : []
        content {
          encryption_key_id = members.value["destination_encryption_key"]["encryption_key_id"]
          vault_id          = members.value["destination_encryption_key"]["vault_id"]
        }
      }
      dynamic "export_mappings" {
        for_each = members.value["member_type"] == "FILE_SYSTEM" ? members.value["export_mappings"] : []
        content {
          destination_mount_target_id = export_mappings.value["destination_mount_target_id"]
          export_id                   = export_mappings.value["export_id"]
        }
      }
      dynamic "file_system_operations" {
        for_each = (members.value["member_type"] == "COMPUTE_INSTANCE_MOVABLE" ||
        members.value["member_type"] == "COMPUTE_INSTANCE_NON_MOVABLE") ? members.value["file_system_operations"] : []
        content {
          export_path = file_system_operations.value["export_path"]
          dynamic "mount_details" {
            for_each = members.value["member_type"] == "COMPUTE_INSTANCE_MOVABLE" && file_system_operations.value["mount_details"] != null ? [1] : []
            content {
              mount_target_id = file_system_operations.value["mount_details"]["mount_target_id"]
            }
          }
          dynamic "unmount_details" {
            for_each = members.value["member_type"] == "COMPUTE_INSTANCE_MOVABLE" && file_system_operations.value["unmount_details"] != null ? [1] : []
            content {
              mount_target_id = file_system_operations.value["unmount_details"]["mount_target_id"]
            }
          }
          mount_point     = file_system_operations.value["mount_point"]
          mount_target_id = file_system_operations.value["mount_target_id"]
        }
      }
      dynamic "load_balancer_mappings" {
        for_each = members.value["member_type"] == "OKE_CLUSTER" ? members.value["load_balancer_mappings"] : []
        content {
          destination_load_balancer_id = load_balancer_mappings.value["destination_load_balancer_id"]
          source_load_balancer_id      = load_balancer_mappings.value["source_load_balancer_id"]
        }
      }
      dynamic "managed_node_pool_configs" {
        for_each = members.value["member_type"] == "OKE_CLUSTER" ? members.value["managed_node_pool_configs"] : []
        content {
          id      = managed_node_pool_configs.value["id"]
          maximum = managed_node_pool_configs.value["maximum"]
          minimum = managed_node_pool_configs.value["minimum"]
        }
      }
      dynamic "network_load_balancer_mappings" {
        for_each = members.value["member_type"] == "OKE_CLUSTER" ? members.value["network_load_balancer_mappings"] : []
        content {
          destination_network_load_balancer_id = network_load_balancer_mappings.value["destination_network_load_balancer_id"]
          source_network_load_balancer_id      = network_load_balancer_mappings.value["source_network_load_balancer_id"]
        }
      }
      dynamic "resource_modifier_mappings" {
        for_each = members.value["member_type"] == "OKE_CLUSTER" ? members.value["resource_modifier_mappings"] : []
        content {
          config_map = resource_modifier_mappings.value["config_map"]
          namespace  = resource_modifier_mappings.value["namespace"]
        }
      }
      dynamic "source_volume_to_destination_encryption_key_mappings" {
        for_each = members.value["member_type"] == "VOLUME_GROUP" ? members.value["source_volume_to_destination_encryption_key_mappings"] : []
        content {
          source_volume_id = source_volume_to_destination_encryption_key_mappings.value["source_volume_id"]
          dynamic "destination_encryption_key" {
            for_each = source_volume_to_destination_encryption_key_mappings.value["destination_encryption_key"] != null ? [1] : []
            content {
              encryption_key_id = source_volume_to_destination_encryption_key_mappings.value["destination_encryption_key"]["encryption_key_id"]
              vault_id          = source_volume_to_destination_encryption_key_mappings.value["destination_encryption_key"]["vault_id"]
            }
          }
        }
      }
      dynamic "vault_mappings" {
        for_each = members.value["member_type"] == "OKE_CLUSTER" ? members.value["vault_mappings"] : []
        content {
          destination_vault_id = vault_mappings.value["destination_vault_id"]
          source_vault_id      = vault_mappings.value["source_vault_id"]
        }
      }
      dynamic "virtual_node_pool_configs" {
        for_each = members.value["member_type"] == "OKE_CLUSTER" ? members.value["virtual_node_pool_configs"] : []
        content {
          id      = virtual_node_pool_configs.value["id"]
          maximum = virtual_node_pool_configs.value["maximum"]
          minimum = virtual_node_pool_configs.value["minimum"]
        }
      }
      dynamic "vnic_mapping" {
        for_each = members.value["member_type"] == "COMPUTE_INSTANCE" ? members.value["vnic_mapping"] : []
        content {
          destination_nsg_id_list = vnic_mapping.value["destination_nsg_id_list"]
          destination_subnet_id   = vnic_mapping.value["destination_subnet_id"]
          source_vnic_id          = vnic_mapping.value["source_vnic_id"]
        }
      }
      dynamic "vnic_mappings" {
        for_each = members.value["member_type"] == "COMPUTE_INSTANCE_MOVABLE" ? members.value["vnic_mappings"] : []
        content {
          destination_nsg_id_list                       = vnic_mappings.value["destination_nsg_id_list"]
          destination_primary_private_ip_address        = vnic_mappings.value["destination_primary_private_ip_address"]
          destination_primary_private_ip_hostname_label = vnic_mappings.value["destination_primary_private_ip_hostname_label"]
          destination_reserved_public_ip_id             = vnic_mappings.value["destination_reserved_public_ip_id"]
          destination_subnet_id                         = vnic_mappings.value["destination_subnet_id"]
          source_vnic_id                                = vnic_mappings.value["source_vnic_id"]
        }
      }
    }
  }
  timeouts {
    create = var.timeouts.create
    update = var.timeouts.update
    delete = var.timeouts.delete
  }
}
