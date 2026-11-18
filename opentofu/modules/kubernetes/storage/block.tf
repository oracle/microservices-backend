# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at https://oss.oracle.com/licenses/upl

resource "oci_core_volume" "pvc" {
  for_each            = local.claims
  compartment_id      = var.compartment_id
  availability_domain = each.value.availability_domain
  display_name        = format("%s-%s", var.label_prefix, each.key)
  size_in_gbs         = each.value.size_in_gbs
  freeform_tags       = { "obaas-fsdr" = var.label_prefix }
}
