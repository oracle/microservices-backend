# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

resource "oci_objectstorage_bucket" "fsdr_logs_region_0" {
  compartment_id = var.compartment_id
  name           = format("%s-logs-%s", var.label_prefix, var.region_0)
  namespace      = var.objectstorage_namespace
}

resource "oci_objectstorage_bucket" "fsdr_logs_region_1" {
  compartment_id = var.compartment_id
  name           = format("%s-logs-%s", var.label_prefix, var.region_1)
  namespace      = var.objectstorage_namespace
  provider       = oci.fsdr_region_1
}

resource "oci_objectstorage_bucket" "fsdr_backup_primary" {
  compartment_id = var.compartment_id
  name           = format("%s-backup-%s", var.label_prefix, var.region_0)
  namespace      = var.objectstorage_namespace
}

resource "oci_objectstorage_bucket" "fsdr_backup_standby" {
  compartment_id = var.compartment_id
  name           = format("%s-backup-%s", var.label_prefix, var.region_1)
  namespace      = var.objectstorage_namespace
  provider       = oci.fsdr_region_1
}
