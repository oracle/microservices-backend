# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at https://oss.oracle.com/licenses/upl

variable "compartment_id" { type = string }
variable "label_prefix" { type = string }
variable "namespace" { type = string }
variable "source_availability_domains" { type = list(string) }
variable "deploy_kafka" { type = bool }
