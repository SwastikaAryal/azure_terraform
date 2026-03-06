###############################################################################
# variables.tf
###############################################################################

variable "location" {
  description = "Primary Azure region"
  type        = string
  default     = "eastus"
}

variable "secondary_location" {
  description = "Secondary Azure region for cross-region restore / DR"
  type        = string
  default     = "westus"
}

variable "resource_group_name" {
  description = "Name of the existing resource group"
  type        = string
  default     = "DefaultResourceGroup-EUS"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "vault_name" {
  description = "Name of the Recovery Services Vault"
  type        = string
  default     = "rsv-minitrue-backup"
}

variable "snapshot_resource_group_name" {
  description = "Resource group for managed disk snapshots"
  type        = string
  default     = "DefaultResourceGroup-EUS"
}

variable "app_vm_ids" {
  description = "List of App VM resource IDs to protect"
  type        = list(string)
  default     = []
}

variable "web_vm_ids" {
  description = "List of Web VM resource IDs to protect"
  type        = list(string)
  default     = []
}

variable "app_vm_os_disk_ids" {
  description = "List of OS disk resource IDs for App VMs (for snapshot policy)"
  type        = list(string)
  default     = []
}

variable "web_vm_os_disk_ids" {
  description = "List of OS disk resource IDs for Web VMs (for snapshot policy)"
  type        = list(string)
  default     = []
}

variable "app_vm_data_disk_ids" {
  description = "List of data disk resource IDs for App VMs"
  type        = list(string)
  default     = []
}

variable "web_vm_data_disk_ids" {
  description = "List of data disk resource IDs for Web VMs"
  type        = list(string)
  default     = []
}

variable "alert_email_addresses" {
  description = "Email addresses for backup failure alerts"
  type        = list(string)
  default     = ["ops-team@example.com"]
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace resource ID for backup diagnostics"
  type        = string
  default     = ""
}

variable "log_analytics_workspace_name" {
  description = "Log Analytics Workspace name"
  type        = string
  default     = "law-minitrue-backup"
}
