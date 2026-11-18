# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

mock_provider "oci" {}

variables {
  compartment_id = "test-compartment"
  display_name   = "test-group"
  log_location   = { bucket = "logs", namespace = "test" }
}

run "encryption_omitted" {
  command = plan
  variables {
    members = [
      {
        member_id   = "volume-group"
        member_type = "VOLUME_GROUP"
        source_volume_to_destination_encryption_key_mappings = [
          {
            source_volume_id = "volume"
          }
        ]
      }
    ]
  }
  assert {
    condition     = length(one(one(oci_disaster_recovery_dr_protection_group.dr_protection_group.members).source_volume_to_destination_encryption_key_mappings).destination_encryption_key) == 0
    error_message = "Incorrect nested values or omitted blocks in encryption_omitted."
  }
}

run "encryption_present" {
  command = plan
  variables {
    members = [
      {
        member_id   = "volume-group"
        member_type = "VOLUME_GROUP"
        source_volume_to_destination_encryption_key_mappings = [
          {
            source_volume_id = "volume"
            destination_encryption_key = {
              encryption_key_id = "key"
              vault_id          = "vault"
            }
          }
        ]
      }
    ]
  }
  assert {
    condition     = one(one(one(oci_disaster_recovery_dr_protection_group.dr_protection_group.members).source_volume_to_destination_encryption_key_mappings).destination_encryption_key).encryption_key_id == "key" && one(one(one(oci_disaster_recovery_dr_protection_group.dr_protection_group.members).source_volume_to_destination_encryption_key_mappings).destination_encryption_key).vault_id == "vault"
    error_message = "Incorrect nested values or omitted blocks in encryption_present."
  }
}

run "mount_0_unmount_0" {
  command = plan
  variables {
    members = [
      {
        member_id   = "compute"
        member_type = "COMPUTE_INSTANCE_MOVABLE"
        file_system_operations = [
          {
            export_path = "/export"
            mount_point = "/mnt"
          }
        ]
      }
    ]
  }
  assert {
    condition     = length(one(one(oci_disaster_recovery_dr_protection_group.dr_protection_group.members).file_system_operations).mount_details) == 0 && length(one(one(oci_disaster_recovery_dr_protection_group.dr_protection_group.members).file_system_operations).unmount_details) == 0
    error_message = "Incorrect nested values or omitted blocks in mount_0_unmount_0."
  }
}

run "mount_1_unmount_0" {
  command = plan
  variables {
    members = [
      {
        member_id   = "compute"
        member_type = "COMPUTE_INSTANCE_MOVABLE"
        file_system_operations = [
          {
            export_path = "/export"
            mount_point = "/mnt"
            mount_details = {
              mount_target_id = "mount-target"
            }
          }
        ]
      }
    ]
  }
  assert {
    condition     = length(one(one(oci_disaster_recovery_dr_protection_group.dr_protection_group.members).file_system_operations).mount_details) == 1 && length(one(one(oci_disaster_recovery_dr_protection_group.dr_protection_group.members).file_system_operations).unmount_details) == 0 && one(one(one(oci_disaster_recovery_dr_protection_group.dr_protection_group.members).file_system_operations).mount_details).mount_target_id == "mount-target"
    error_message = "Incorrect nested values or omitted blocks in mount_1_unmount_0."
  }
}

run "mount_0_unmount_1" {
  command = plan
  variables {
    members = [
      {
        member_id   = "compute"
        member_type = "COMPUTE_INSTANCE_MOVABLE"
        file_system_operations = [
          {
            export_path = "/export"
            mount_point = "/mnt"
            unmount_details = {
              mount_target_id = "unmount-target"
            }
          }
        ]
      }
    ]
  }
  assert {
    condition     = length(one(one(oci_disaster_recovery_dr_protection_group.dr_protection_group.members).file_system_operations).mount_details) == 0 && length(one(one(oci_disaster_recovery_dr_protection_group.dr_protection_group.members).file_system_operations).unmount_details) == 1 && one(one(one(oci_disaster_recovery_dr_protection_group.dr_protection_group.members).file_system_operations).unmount_details).mount_target_id == "unmount-target"
    error_message = "Incorrect nested values or omitted blocks in mount_0_unmount_1."
  }
}

run "mount_1_unmount_1" {
  command = plan
  variables {
    members = [
      {
        member_id   = "compute"
        member_type = "COMPUTE_INSTANCE_MOVABLE"
        file_system_operations = [
          {
            export_path = "/export"
            mount_point = "/mnt"
            mount_details = {
              mount_target_id = "mount-target"
            }
            unmount_details = {
              mount_target_id = "unmount-target"
            }
          }
        ]
      }
    ]
  }
  assert {
    condition     = length(one(one(oci_disaster_recovery_dr_protection_group.dr_protection_group.members).file_system_operations).mount_details) == 1 && length(one(one(oci_disaster_recovery_dr_protection_group.dr_protection_group.members).file_system_operations).unmount_details) == 1 && one(one(one(oci_disaster_recovery_dr_protection_group.dr_protection_group.members).file_system_operations).mount_details).mount_target_id == "mount-target" && one(one(one(oci_disaster_recovery_dr_protection_group.dr_protection_group.members).file_system_operations).unmount_details).mount_target_id == "unmount-target"
    error_message = "Incorrect nested values or omitted blocks in mount_1_unmount_1."
  }
}

run "oke_resource_modifiers" {
  command = plan
  variables {
    members = [{
      member_id                  = "oke-cluster"
      member_type                = "OKE_CLUSTER"
      peer_cluster_id            = "peer-cluster"
      resource_modifier_mappings = [{ config_map = "dr-resources", namespace = "obaas" }]
    }]
    timeouts = { create = "40m", update = "30m", delete = "25m" }
  }
  assert {
    condition     = one(one(oci_disaster_recovery_dr_protection_group.dr_protection_group.members).resource_modifier_mappings).config_map == "dr-resources" && one(one(oci_disaster_recovery_dr_protection_group.dr_protection_group.members).resource_modifier_mappings).namespace == "obaas"
    error_message = "OKE resource modifiers must reach the protection group."
  }
  assert {
    condition     = oci_disaster_recovery_dr_protection_group.dr_protection_group.timeouts.create == "40m" && oci_disaster_recovery_dr_protection_group.dr_protection_group.timeouts.delete == "25m"
    error_message = "Group operation timeouts must be configurable."
  }
}
