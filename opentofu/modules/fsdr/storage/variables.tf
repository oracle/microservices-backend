# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at https://oss.oracle.com/licenses/upl

variable "compartment_id" { type = string }
variable "label_prefix" { type = string }
variable "destination_ad" { type = string }
variable "init_destroy" {
  type    = bool
  default = false
}
variable "volumes" {
  type = map(object({ id = string, availability_domain = string }))
}
