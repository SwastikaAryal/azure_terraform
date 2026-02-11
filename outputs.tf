# =================================================================================================
# File: terraform/modules/backup_vault/outputs.tf
# =================================================================================================

output "backup_vault_id" {
  description = "The ID of the backup vault"
  value       = var.enable_backup_vault ? module.bmw_backup_vault[0].backup_vault_id : null
}

output "backup_vault_name" {
  description = "The name of the backup vault"
  value       = var.enable_backup_vault ? module.bmw_backup_vault[0].backup_vault_name : null
}

output "action_group_id" {
  description = "The ID of the monitoring action group"
  value       = var.enable_backup_vault ? azurerm_monitor_action_group.this[0].id : null
}

output "metric_alert_id" {
  description = "The ID of the metric alert"
  value       = var.enable_backup_vault ? azurerm_monitor_metric_alert.this[0].id : null
}

output "management_lock_id" {
  description = "The ID of the management lock"
  value       = var.enable_backup_vault ? azurerm_management_lock.backup_lock[0].id : null
}
