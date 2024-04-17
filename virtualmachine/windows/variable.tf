variable "resource_group_name" {
  type        = string
  default     = null
  description = "The name of the resource group where the resources will be created."
}

variable "location" {
  type        = string
  default     = null
  description = "The Azure region where the resources will be deployed."
}

variable "vm_name" {
  type        = string
  default     = null
  description = "The name of the virtual machine."
}

variable "username" {
  type        = string
  default     = null
  description = "The username for logging into the virtual machine."
}

variable "password" {
  type        = string
  default     = null
  description = "The password for logging into the virtual machine."
}

variable "subnet" {
  type        = string
  default     = null
  description = "The name of the subnet where the VM will be deployed."
}

variable "vnet" {
  type        = string
  default     = null
  description = "The name of the virtual network where the VM will be deployed."
}

variable "vmnetwork" {
  type        = string
  default     = null
  description = "The name of the virtual machine network."
}

variable "nic_name" {
  type        = string
  default     = null
  description = "The name of the network interface card for the VM."
}

variable "size" {
  type        = string
  default     = null
  description = "The size of the virtual machine."
}

variable "storage_account_type" {
  type        = string
  default     = null
  description = "The type of storage account to use for the virtual machine disks."
}

variable "ip_config_name" {
  type        = string
  default     = null
  description = "The name of the IP configuration for the VM's network interface."
}

variable "private_ip_address_allocation" {
  type        = string
  default     = null
  description = "The method used to assign the private IP address to the VM."
}

variable "caching" {
  type        = string
  default     = null
  description = "The caching type for the OS disk."
}

variable "source_image_id" {
  type        = string
  default     = null
  description = "The ID of the source image for the virtual machine."
}
