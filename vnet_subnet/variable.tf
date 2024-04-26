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

variable "security_group_name" {
  description = "Name of the Azure network security group"
  type        = string
  default     = null
}

variable "virtual_network_name" {
  description = "Name of the Azure virtual network"
  type        = string
  default     = null
}

variable "address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = null
}

variable "dns_servers" {
  description = "DNS servers for the virtual network"
  type        = list(string)
  default     = null
}

variable "subnet1_name" {
  description = "Name of subnet1"
  type        = string
  default     = null
}

variable "subnet1_prefix" {
  description = "Address prefix for subnet1"
  type        = string
  default     = null
}

variable "subnet2_name" {
  description = "Name of subnet2"
  type        = string
  default     = null
}

variable "subnet2_prefix" {
  description = "Address prefix for subnet2"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags for the resources"
  type        = map(string)
  default     = null
}
