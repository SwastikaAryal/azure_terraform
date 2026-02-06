# =================================================================================================
# File: terraform/modules/storage_account/variables.tf
# =================================================================================================

# Global Configuration
variable "global_config" {
  description = "Global configuration object"
  type        = any
}

variable "cloud_region" {
  description = "Azure cloud region for the storage account"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

# Storage Account Configuration
variable "account_tier" {
  description = "Defines the Tier to use for this storage account (Standard or Premium)"
  type        = string
  default     = "Standard"
}

variable "account_replication_type" {
  description = "Defines the type of replication to use for this storage account"
  type        = string
  default     = "GRS"
}

variable "account_kind" {
  description = "Defines the Kind of account"
  type        = string
  default     = "StorageV2"
}

variable "public_network_access_enabled" {
  description = "Whether the public network access is enabled"
  type        = bool
  default     = false
}

variable "shared_access_key_enabled" {
  description = "Indicates whether the storage account permits requests to be authorized with the account access key via Shared Key"
  type        = bool
  default     = false
}

variable "default_to_oauth_authentication" {
  description = "Default to Azure Active Directory authorization in the Azure portal when accessing the Storage Account"
  type        = bool
  default     = true
}

# Customer Managed Key (CMK) Configuration
variable "enable_cmk" {
  description = "Enable Customer Managed Key encryption"
  type        = bool
  default     = false
}

variable "cmk_key_name" {
  description = "The name of the customer managed key"
  type        = string
  default     = null
}

variable "cmk_key_vault_id" {
  description = "The ID of the Key Vault where the customer managed key is stored"
  type        = string
  default     = null
}

variable "cmk_user_assigned_identity_id" {
  description = "The ID of the user assigned identity for CMK"
  type        = string
  default     = null
}

# Diagnostic Settings
variable "create_diagnostic_settings" {
  description = "Whether to create diagnostic settings"
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics Workspace"
  type        = string
  default     = null
}

# Storage Properties
variable "queue_properties" {
  description = "Queue properties configuration"
  type        = any
  default     = {}
}

variable "blob_properties" {
  description = "Blob properties configuration"
  type        = any
  default     = {}
}

variable "share_properties" {
  description = "File share properties configuration"
  type        = any
  default     = {}
}

# Naming and Tagging
variable "custom_name_suffix" {
  description = "Custom name suffix for the storage account"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "naming_file_json_tpl" {
  description = "Path to the naming template JSON file"
  type        = string
}

# Network Configuration
variable "allowed_ips" {
  description = "List of allowed IP addresses"
  type        = list(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = "List of allowed subnet IDs"
  type        = list(string)
  default     = []
}

variable "create_private_endpoint" {
  description = "Whether to create a private endpoint"
  type        = bool
  default     = false
}

# Storage Management Policy
variable "storage_management_policy" {
  description = "Storage lifecycle management policy configuration"
  type = object({
    rules = list(object({
      name    = string
      enabled = optional(bool, true)
      filters = object({
        prefix_match = optional(list(string), [])
        blob_types   = optional(list(string), ["blockBlob"])
        match_blob_index_tag = optional(object({
          name      = string
          operation = optional(string, "==")
          value     = string
        }))
      })
      actions = object({
        base_blob = object({
          tier_to_cool_after_days_since_modification_greater_than    = optional(number)
          tier_to_archive_after_days_since_modification_greater_than = optional(number)
          delete_after_days_since_modification_greater_than          = optional(number)
        })
        snapshot = optional(object({
          delete_after_days_since_creation_greater_than        = optional(number)
          change_tier_to_archive_after_days_since_creation     = optional(number)
          change_tier_to_cool_after_days_since_creation        = optional(number)
        }))
        version = optional(object({
          change_tier_to_archive_after_days_since_creation = optional(number)
          change_tier_to_cool_after_days_since_creation    = optional(number)
          delete_after_days_since_creation                 = optional(number)
        }))
      })
    }))
  })
  default = {
    rules = []
  }
}

# Monitoring Configuration
variable "monitoring" {
  description = "Monitoring and alerting configuration"
  type = object({
    enabled = bool
    action_group = object({
      name       = string
      short_name = string
      webhook_receivers = optional(list(object({
        name                    = string
        service_uri             = string
        use_common_alert_schema = optional(bool, true)
      })), [])
      email_receivers = optional(list(object({
        name                    = string
        email_address           = string
        use_common_alert_schema = optional(bool, true)
      })), [])
    })
    metric_alert = object({
      name        = string
      scopes      = list(string)
      description = optional(string, "Storage Account Metric Alert")
      severity    = optional(number, 3)
      frequency   = optional(string, "PT5M")
      window_size = optional(string, "PT15M")
      enabled     = optional(bool, true)
      criteria = object({
        metric_namespace = string
        metric_name      = string
        aggregation      = string
        operator         = string
        threshold        = number
        dimension = optional(object({
          name     = string
          operator = string
          values   = list(string)
        }))
      })
    })
  })
  default = null
}

# Security Configuration
variable "enable_defender_for_storage" {
  description = "Enable Microsoft Defender for Storage"
  type        = bool
  default     = false
}
