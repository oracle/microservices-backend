# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at https://oss.oracle.com/licenses/upl

output "members" {
  value = [for group in oci_core_volume_group.pvc : {
    member_id                  = group.id
    member_type                = "VOLUME_GROUP"
    destination_compartment_id = var.compartment_id
  }]
}

