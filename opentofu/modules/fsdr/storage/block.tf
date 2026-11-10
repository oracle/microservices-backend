# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

resource "oci_core_volume_group" "pvc" {
  for_each            = local.volume_ids_by_ad
  compartment_id      = var.compartment_id
  availability_domain = each.key
  display_name        = format("%s-pvc", var.label_prefix)
  freeform_tags       = { "obaas-fsdr" = var.label_prefix }
  volume_ids          = each.value
  source_details {
    type       = "volumeIds"
    volume_ids = each.value
  }
  volume_group_replicas_deletion = var.init_destroy
  preserve_volume_replica        = var.init_destroy ? false : null
  dynamic "volume_group_replicas" {
    for_each = var.init_destroy ? [] : [var.destination_ad]
    content {
      availability_domain = volume_group_replicas.value
      display_name        = var.label_prefix
    }
  }
  lifecycle {
    # OCI reverses replication during recovery.
    ignore_changes = [source_details, volume_group_replicas]
  }
}
