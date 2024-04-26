variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = null
}

variable "location" {
  description = "Location of the Azure resources"
  type        = string
  default     = null
}

variable "route_table_name" {
  description = "Name of the Azure route table"
  type        = string
  default     = null
}

variable "disable_bgp_route_propagation" {
  description = "Whether to disable BGP route propagation"
  type        = bool
  default     = null
}

variable "route1_address_prefix" {
  description = "Destination prefix for route1"
  type        = string
  default     = null
}

variable "route1_next_hop_type" {
  description = "Type of the next hop for route1"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags for the resources"
  type        = map(string)
  default     = null
}
