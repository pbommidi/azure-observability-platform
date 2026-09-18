# Variables are INPUTS to the configuration. Declaring a type means
# Terraform rejects a wrong value at plan time rather than failing
# halfway through an apply — the same fail-fast reasoning as
# _required() in config/settings.py.

variable "location" {
  description = "Azure region for all resources. Must have capacity for the AKS node sizes used in Part 2."
  type        = string
  default     = "southindia"
}

variable "resource_group_name" {
  description = "Resource group holding the entire Day 2 environment. Also the cleanup boundary."
  type        = string
  default     = "rg-obs-day2"
}

variable "app_vnet_cidr" {
  description = "Address space for the application network. Must NOT overlap the monitoring network — overlapping ranges cannot be peered, ever."
  type        = string
  default     = "10.10.0.0/16"
}

variable "mon_vnet_cidr" {
  description = "Address space for the monitoring network."
  type        = string
  default     = "10.20.0.0/16"
}

variable "app_subnet_cidr" {
  description = "Subnet for the application AKS node pool. A /20 gives 4096 addresses — generous, because Azure CNI assigns an IP per POD, not per node."
  type        = string
  default     = "10.10.0.0/20"
}

variable "mon_subnet_cidr" {
  description = "Subnet for the monitoring AKS node pool."
  type        = string
  default     = "10.20.0.0/20"
}

variable "tags" {
  description = "Applied to every resource. Tags are how you attribute cost and find things later."
  type        = map(string)
  default = {
    project     = "prometheus-workshop-day2"
    managed_by  = "terraform"
    environment = "learning"
  }
}

variable "node_size" {
  description = "VM size for AKS node. D2ds_v6 chosen because the DSv5 family has zero quota on this subscription — a constraint discovered, not preferred."
  type        = string
  default     = "Standard_D2ds_v6"
}

variable "node_count" {
  description = "Nodes per cluster. Two rather than one so pod scheduling across nodes is observable."
  type        = number
  default     = 2
}

variable "kubernetes_version" {
  description = "AKS version. The workshop is tested on 1.30, but the latest available is always acceptable."
  type        = string
  default     = null
}

variable "storage_account_tier" {
  description = "Standard vs Premium. Standard is fine — Thanos, Loki and Tempo are not latency-sensitive enough to need Premium's SSD-backed storage."
  type        = string
  default     = "Standard"
}

variable "storage_replication_type" {
  description = "LRS = locally redundant, cheapest, one datacenter. GRS replicates cross-region for production durability. LRS is correct for a PoC."
  type        = string
  default     = "LRS"
}