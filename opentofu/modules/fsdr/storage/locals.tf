# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  volume_ids_by_ad = { for ad in distinct([for volume in var.volumes : volume.availability_domain]) : ad => [
    for volume in var.volumes : volume.id if volume.availability_domain == ad
  ] }
}
