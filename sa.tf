# =================================================================================================
# File: terraform/modules/storage_account/main.tf
# =================================================================================================

locals {
  naming_template = var.naming_file_json_tpl
}

# NOTE: You need FPC Owner Role to deploy Storage Account
module "bmw_storage_account" {
  source                          = "git::https://atc-github.azure.cloud.bmw/cgbp/terraform-azure-bmw-storage.git?ref=5.0.4"
  global_config                   = var.global_config
  cloud_region                    = var.cloud_region
  resource_group_name             = var.resource_group_name
  account_tier                    = var.account_tier
  account_replication_type        = var.account_replication_type
  account_kind                    = var.account_kind
  public_network_access_enabled   = var.public_network_access_enabled
  shared_access_key_enabled       = var.shared_access_key_enabled
  default_to_oauth_authentication = var.default_to_oauth_authentication
  enable_cmek_key                 = var.enable_cmk
  customer_managed_key_name       = var.enable_cmk ? var.cmk_key_name : null
  customer_managed_key_vault_id   = var.enable_cmk ? var.cmk_key_vault_id : null
  user_assigned_identity_id       = var.enable_cmk ? var.cmk_user_assigned_identity_id : null
  create_user_assigned_identity   = true
  enable_logging                  = var.create_diagnostic_settings
  log_analytics_workspace_id      = var.create_diagnostic_settings ? var.log_analytics_workspace_id : null
  queue_properties                = var.queue_properties
  blob_properties                 = var.blob_properties
  share_properties                = var.share_properties
  custom_name                     = var.custom_name_suffix
  custom_tags                     = var.tags
  naming_file_json_tpl            = var.naming_file_json_tpl
  allowed_ips                     = var.allowed_ips
  allowed_subnet_ids              = var.allowed_subnet_ids
  create_private_endpoint         = var.create_private_endpoint
  azure_files_authentication = {
    directory_type                 = "AADKERB" # Assumes you are using Microsoft Entra Kerberos
    default_share_level_permission = "StorageFileDataSmbShareContributor"
  }
}

# Storage Management Policy
resource "azurerm_storage_management_policy" "this" {
  count = var.storage_management_policy != null && length(var.storage_management_policy.rules) > 0 ? 1 : 0

  storage_account_id = module.bmw_storage_account.id

  dynamic "rule" {
    for_each = var.storage_management_policy.rules

    content {
      name    = rule.value.name
      enabled = lookup(rule.value, "enabled", true)

      filters {
        prefix_match = lookup(rule.value.filters, "prefix_match", [])
        blob_types   = lookup(rule.value.filters, "blob_types", ["blockBlob"])

        dynamic "match_blob_index_tag" {
          for_each = lookup(rule.value.filters, "match_blob_index_tag", null) != null ? [rule.value.filters.match_blob_index_tag] : []

          content {
            name      = match_blob_index_tag.value.name
            operation = lookup(match_blob_index_tag.value, "operation", "==")
            value     = match_blob_index_tag.value.value
          }
        }
      }

      actions {
        base_blob {
          tier_to_cool_after_days_since_modification_greater_than    = lookup(rule.value.actions.base_blob, "tier_to_cool_after_days_since_modification_greater_than", null)
          tier_to_archive_after_days_since_modification_greater_than = lookup(rule.value.actions.base_blob, "tier_to_archive_after_days_since_modification_greater_than", null)
          delete_after_days_since_modification_greater_than          = lookup(rule.value.actions.base_blob, "delete_after_days_since_modification_greater_than", null)
        }

        dynamic "snapshot" {
          for_each = lookup(rule.value.actions, "snapshot", null) != null ? [rule.value.actions.snapshot] : []

          content {
            delete_after_days_since_creation_greater_than        = lookup(snapshot.value, "delete_after_days_since_creation_greater_than", null)
            change_tier_to_archive_after_days_since_creation     = lookup(snapshot.value, "change_tier_to_archive_after_days_since_creation", null)
            change_tier_to_cool_after_days_since_creation        = lookup(snapshot.value, "change_tier_to_cool_after_days_since_creation", null)
          }
        }

        dynamic "version" {
          for_each = lookup(rule.value.actions, "version", null) != null ? [rule.value.actions.version] : []

          content {
            change_tier_to_archive_after_days_since_creation = lookup(version.value, "change_tier_to_archive_after_days_since_creation", null)
            change_tier_to_cool_after_days_since_creation    = lookup(version.value, "change_tier_to_cool_after_days_since_creation", null)
            delete_after_days_since_creation                 = lookup(version.value, "delete_after_days_since_creation", null)
          }
        }
      }
    }
  }
}

# Monitor Action Group
resource "azurerm_monitor_action_group" "this" {
  count = var.monitoring != null && var.monitoring.enabled ? 1 : 0

  name                = var.monitoring.action_group.name
  resource_group_name = var.resource_group_name
  short_name          = var.monitoring.action_group.short_name

  dynamic "webhook_receiver" {
    for_each = lookup(var.monitoring.action_group, "webhook_receivers", [])

    content {
      name                    = webhook_receiver.value.name
      service_uri             = webhook_receiver.value.service_uri
      use_common_alert_schema = lookup(webhook_receiver.value, "use_common_alert_schema", true)
    }
  }

  dynamic "email_receiver" {
    for_each = lookup(var.monitoring.action_group, "email_receivers", [])

    content {
      name                    = email_receiver.value.name
      email_address           = email_receiver.value.email_address
      use_common_alert_schema = lookup(email_receiver.value, "use_common_alert_schema", true)
    }
  }
}

# Monitor Metric Alert
resource "azurerm_monitor_metric_alert" "this" {
  count = var.monitoring != null && var.monitoring.enabled ? 1 : 0

  name                = var.monitoring.metric_alert.name
  resource_group_name = var.resource_group_name
  scopes              = var.monitoring.metric_alert.scopes
  description         = lookup(var.monitoring.metric_alert, "description", "Storage Account Metric Alert")
  severity            = lookup(var.monitoring.metric_alert, "severity", 3)
  frequency           = lookup(var.monitoring.metric_alert, "frequency", "PT5M")
  window_size         = lookup(var.monitoring.metric_alert, "window_size", "PT15M")
  enabled             = lookup(var.monitoring.metric_alert, "enabled", true)

  criteria {
    metric_namespace = var.monitoring.metric_alert.criteria.metric_namespace
    metric_name      = var.monitoring.metric_alert.criteria.metric_name
    aggregation      = var.monitoring.metric_alert.criteria.aggregation
    operator         = var.monitoring.metric_alert.criteria.operator
    threshold        = var.monitoring.metric_alert.criteria.threshold

    dynamic "dimension" {
      for_each = lookup(var.monitoring.metric_alert.criteria, "dimension", null) != null ? [var.monitoring.metric_alert.criteria.dimension] : []

      content {
        name     = dimension.value.name
        operator = dimension.value.operator
        values   = dimension.value.values
      }
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.this[0].id
  }

  depends_on = [azurerm_monitor_action_group.this]
}

# Security Center Subscription Pricing
resource "azurerm_security_center_subscription_pricing" "main" {
  count = var.enable_defender_for_storage ? 1 : 0

  tier          = "Standard"
  resource_type = "StorageAccounts"
}
