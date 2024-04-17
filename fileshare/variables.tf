variable "resource_group_name" {
  type        = string
  description = "The name of the resource group where the resources will be deployed."
  default     = null
}

variable "resource_group_location" {
  type        = string
  description = "The location of the resource group."
  default     = null
}

variable "storage_account_name" {
  type        = string
  description = "The name of the storage account."
  default     = null
}

variable "storage_account_tier" {
  type        = string
  description = "The tier of the storage account."
  default     = null
}

variable "storage_account_replication_type" {
  type        = string
  description = "The replication type of the storage account."
  default     = null
}

variable "storage_share_name" {
  type        = string
  description = "The name of the storage share."
  default     = null
}

variable "storage_share_quota" {
  type        = number
  description = "The quota for the storage share in GB."
  default     = null
}

variable "storage_share_file_name" {
  type        = string
  description = "The name of the file in the storage share."
  default     = null
}
