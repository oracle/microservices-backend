# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at https://oss.oracle.com/licenses/upl

mock_provider "oci" {}

variables {
  compartment_id = "test-compartment"
  label_prefix   = "storagetest"
  destination_ad = "TEST:CWL-AD-1"
  volumes = {
    first  = { id = "volume-1", availability_domain = "TEST:LHR-AD-1" }
    second = { id = "volume-2", availability_domain = "TEST:LHR-AD-1" }
  }
}

run "updateable_volume_membership" {
  command = plan

  assert {
    condition     = toset(oci_core_volume_group.pvc["TEST:LHR-AD-1"].volume_ids) == toset(["volume-1", "volume-2"])
    error_message = "Volume groups must expose updateable membership for newly provisioned persistent volumes."
  }
  assert {
    condition     = toset(one(oci_core_volume_group.pvc["TEST:LHR-AD-1"].source_details).volume_ids) == toset(oci_core_volume_group.pvc["TEST:LHR-AD-1"].volume_ids)
    error_message = "Volume group creation and update membership must use the same volume inventory."
  }
}
