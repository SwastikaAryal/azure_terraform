variable "resource_group_name" {
  type        = string
  description = "The name of the resource group where the resources will be deployed."
  default     = null
}

variable "location" {
  type        = string
  description = "The location where the resources will be deployed."
  default     = null
}

variable "account_name" {
  type        = string
  description = "The name of the storage account."
  default     = null
}

variable "account_tier" {
  type        = string
  description = "The storage account tier."
  default     = null
}

variable "account_replication_type" {
  type        = string
  description = "The replication type for the storage account."
  default     = null
}

variable "environment" {
  type        = string
  description = "The environment where the resources will be deployed (e.g., dev, test, prod)."
  default     = null
}

variable "default_action" {
  type        = string
  description = "The default action for a resource."
  default     = null
}

variable "subnet_id" {
  type        = string
  description = "The ID of the subnet where the resources will be deployed."
  default     = null
}
