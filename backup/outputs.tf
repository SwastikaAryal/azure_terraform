###############################################################################
# outputs.tf
###############################################################################

output "recovery_services_vault_id" {
  description = "Resource ID of the Recovery Services Vault (MINITRUE-9348)"
  value       = azurerm_recovery_services_vault.main.id
}

output "recovery_services_vault_name" {
  description = "Name of the Recovery Services Vault"
  value       = azurerm_recovery_services_vault.main.name
}

# output "data_protection_backup_vault_id" {
#   description = "Resource ID of the Data Protection Backup Vault for disk snapshots (MINITRUE-9416)"
#   value       = azurerm_data_protection_backup_vault.disk_vault.id
# }

output "automation_account_name" {
  description = "Automation Account name for restore runbooks (MINITRUE-9414)"
  value       = azurerm_automation_account.backup_restore.name
}

output "action_group_id" {
  description = "Action Group ID for backup alerts (Sprint 3)"
  value       = azurerm_monitor_action_group.backup_alerts.id
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID used for backup diagnostics"
  value       = local.law_id
}


# -----------------------------------------------------------------
# Output policy IDs for reference / cross-module use
# -----------------------------------------------------------------
output "standard_backup_policy_id" {
  description = "Resource ID of the Standard VM backup policy"
  value       = azurerm_backup_policy_vm.standard.id
}

output "enhanced_backup_policy_id" {
  description = "Resource ID of the Enhanced VM backup policy"
  value       = azurerm_backup_policy_vm.enhanced.id
}
