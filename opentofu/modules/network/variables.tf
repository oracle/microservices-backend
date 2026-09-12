# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

variable "compartment_id" {
  type = string
}

variable "label_prefix" {
  type = string
}

variable "vcn_cidr" {
  type    = list(string)
  default = ["10.42.0.0/16"]
}

variable "oci_services" {
  description = "OCI Services Network object containing id, name, and cidr_block"
  type = object({
    cidr_block = string
    id         = string
    name       = string
  })
}