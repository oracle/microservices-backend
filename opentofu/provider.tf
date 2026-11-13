# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 9.12.1" // Last evaluated 9-Nov-26
    }
  }
  required_version = ">= 1.5"
}

data "oci_identity_region_subscriptions" "tenancy" {
  tenancy_id = var.tenancy_ocid
}

locals {
  home_region = one([for subscription in data.oci_identity_region_subscriptions.tenancy.region_subscriptions : subscription.region_name if subscription.is_home_region])
  user_ocid   = var.user_ocid != "" ? var.user_ocid : var.current_user_ocid
}

provider "oci" {
  region           = var.region
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = local.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  private_key      = var.private_key
}

provider "oci" {
  region           = local.home_region
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = local.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  private_key      = var.private_key
  alias            = "home_region"
}

provider "oci" {
  region           = var.fsdr_region_1 != "" ? var.fsdr_region_1 : var.region
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = local.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  private_key      = var.private_key
  alias            = "fsdr_region_1"
}
