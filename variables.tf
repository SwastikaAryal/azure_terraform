# =================================================================================================
# File: terraform/modules/backup_vault/variables.tf
# =================================================================================================

variable "enable_backup_vault" {
  type        = bool
  default     = false
  description = "Flag to enable or disable creation of the backup vault."
}

variable "global_config" {
  type        = any
  description = "Global configuration object containing customer_prefix, env, etc."
}

variable "cloud_region" {
  type        = string
  description = "Define the location which tf should use."
}

variable "location" {
  type        = string
  description = "Azure region where the backup vault will be deployed."
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group for the backup vault."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to the backup vault."
}

variable "datastore_type" {
  type        = string
  default     = "VaultStore"
  description = "Type of datastore to use for the backup vault."
}

variable "redundancy" {
  type        = string
  default     = "LocallyRedundant"
  description = "Redundancy setting for the backup vault (e.g., LocallyRedundant, GeoRedundant)."
}

variable "soft_delete_state" {
  type        = string
  default     = "On"
  description = "State of soft delete feature ('On' or 'Off')."
}

variable "retention_duration_in_days" {
  type        = number
  default     = 14
  description = "Retention duration in days for soft-deleted items."
}

variable "naming_file_json_tpl" {
  type        = any
  description = "The common naming template file"
  default     = null
}

# Monitoring Configuration
variable "monitoring" {
  description = "Azure Monitor Action Group and Metric Alert configuration"
  type = object({
    action_group = object({
      name                = string
      short_name          = string
      resource_group_name = string

      webhook_receivers = list(object({
        name        = string
        service_uri = string
      }))
    })

    metric_alert = object({
      name                = string
      resource_group_name = string
      scopes              = list(string)
      description         = string

      criteria = object({
        metric_namespace = string
        metric_name      = string
        aggregation      = string
        operator         = string
        threshold        = number

        dimension = object({
          name     = string
          operator = string
          values   = list(string)
        })
      })
    })
  })
}
