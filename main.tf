# =================================================================================================
# File: terraform/modules/backup_vault/main.tf
# =================================================================================================

locals {
  effective_bv_custom_name = format("%s-bv-%s", lower(var.global_config.customer_prefix), lower(var.global_config.env))
  naming_template          = var.naming_file_json_tpl
}

module "common" {
  source        = "git::https://atc-github.azure.cloud.bmw/cgbp/terraform-bmw-cloud-commons.git?ref=2.4.0"
  cloud_region  = var.cloud_region
  global_config = var.global_config
}

module "bmw_backup_vault" {
  source                     = "git::https://atc-github.azure.cloud.bmw/cgbp/terraform-azure-bmw-backup-vault.git?ref=2.0.2"
  count                      = var.enable_backup_vault ? 1 : 0
  global_config              = var.global_config
  cloud_region               = var.location
  resource_group_name        = var.resource_group_name
  datastore_type             = var.datastore_type
  redundancy                 = var.redundancy
  soft_delete                = var.soft_delete_state
  retention_duration_in_days = var.soft_delete_state == "On" ? var.retention_duration_in_days : null
  custom_tags                = var.tags
  naming_file_json_tpl       = var.naming_file_json_tpl
  enable_diagnostic_settings = true
}

# Add the current User to the Backup Multi User Admin Group
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "backup_role" {
  count                = var.enable_backup_vault ? 1 : 0
  scope                = module.bmw_backup_vault[0].backup_vault_id
  role_definition_name = "Backup MUA Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Azure Monitor Action Group
resource "azurerm_monitor_action_group" "this" {
  count               = var.enable_backup_vault ? 1 : 0
  name                = var.monitoring.action_group.name
  resource_group_name = var.resource_group_name
  short_name          = var.monitoring.action_group.short_name

  dynamic "webhook_receiver" {
    for_each = var.monitoring.action_group.webhook_receivers

    content {
      name        = webhook_receiver.value.name
      service_uri = webhook_receiver.value.service_uri
    }
  }
}

# Azure Monitor Metric Alert
resource "azurerm_monitor_metric_alert" "this" {
  count               = var.enable_backup_vault ? 1 : 0
  name                = var.monitoring.metric_alert.name
  resource_group_name = var.resource_group_name
  scopes              = var.monitoring.metric_alert.scopes
  description         = var.monitoring.metric_alert.description

  criteria {
    metric_namespace = var.monitoring.metric_alert.criteria.metric_namespace
    metric_name      = var.monitoring.metric_alert.criteria.metric_name
    aggregation      = var.monitoring.metric_alert.criteria.aggregation
    operator         = var.monitoring.metric_alert.criteria.operator
    threshold        = var.monitoring.metric_alert.criteria.threshold

    dimension {
      name     = var.monitoring.metric_alert.criteria.dimension.name
      operator = var.monitoring.metric_alert.criteria.dimension.operator
      values   = var.monitoring.metric_alert.criteria.dimension.values
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.this[0].id
  }
}

# Management Lock
resource "azurerm_management_lock" "backup_lock" {
  count      = var.enable_backup_vault ? 1 : 0
  name       = "backup_vault_protection"
  scope      = module.bmw_backup_vault[0].backup_vault_id
  lock_level = "CanNotDelete"
  notes      = "Locked because it's needed by a third-party"
}
