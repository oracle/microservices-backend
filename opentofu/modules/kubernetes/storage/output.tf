# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at https://oss.oracle.com/licenses/upl

output "persistent_storage" {
  value = {
    chart = local.chart_storage
    volumes = { for key, volume in oci_core_volume.pvc : key => {
      id                  = volume.id
      claim_name          = local.claims[key].claim_name
      namespace           = var.namespace
      size_in_gbs         = local.claims[key].size_in_gbs
      availability_domain = local.claims[key].availability_domain
    } }
  }
}
