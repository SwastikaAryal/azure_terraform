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

variable "law_name" {
  description = "Name of the Log Analytics Workspace"
  type        = string
  default     = null
}

variable "sku" {
  description = "SKU (pricing tier) of the Log Analytics Workspace"
  type        = string
  default     = null
}

variable "retention_in_days" {
  description = "Retention period in days for Log Analytics data"
  type        = string
  default     = null
}
