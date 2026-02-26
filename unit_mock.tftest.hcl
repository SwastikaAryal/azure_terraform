###############################################################################
# tests/unit_mock.tftest.hcl
#
# Pure unit tests using the mock azurerm provider.
# Runs without any Azure credentials – safe for CI on every commit.
#
# Covers the highest-value assertions across all four MINITRUE stories
# and Sprint 3, using mocked resource responses.
#
# Run:  terraform test -filter=tests/unit_mock.tftest.hcl
###############################################################################

variables {
  location                     = "eastus"
  secondary_location           = "westus"
  resource_group_name          = "rg-minitrue-test"
  environment                  = "test"
  vault_name                   = "rsv-minitrue-unit-test"
  snapshot_resource_group_name = "rg-minitrue-snaps-test"
  alert_email_addresses        = ["ops-test@example.com"]
  log_analytics_workspace_id   = ""
  log_analytics_workspace_name = "law-minitrue-test"
  app_vm_ids                   = []
  web_vm_ids                   = []
  app_vm_os_disk_ids           = []
  web_vm_os_disk_ids           = []
  app_vm_data_disk_ids         = []
  web_vm_data_disk_ids         = []
}

# Use the mock provider for all runs in this file
mock_provider "azurerm" {}

###############################################################################
# MINITRUE-9348 – Vault config
###############################################################################
run "unit_vault_soft_delete_enabled" {
  command = plan

  assert {
    condition     = azurerm_recovery_services_vault.main.soft_delete_enabled == true
    error_message = "[UNIT] soft-delete must be true in module config (MINITRUE-9348)"
  }

  assert {
    condition     = azurerm_recovery_services_vault.main.sku == "Standard"
    error_message = "[UNIT] vault SKU must be Standard"
  }

  assert {
    condition     = azurerm_recovery_services_vault.main.storage_mode_type == "GeoRedundant"
    error_message = "[UNIT] storage mode must be GeoRedundant"
  }

  assert {
    condition     = azurerm_recovery_services_vault.main.cross_region_restore_enabled == true
    error_message = "[UNIT] cross-region restore must be enabled"
  }
}

###############################################################################
# MINITRUE-9418 – Standard policy retention values
###############################################################################
run "unit_standard_policy_retention" {
  command = plan

  assert {
    condition     = azurerm_backup_policy_vm.standard.backup[0].frequency == "Daily"
    error_message = "[UNIT] standard policy frequency must be Daily"
  }

  assert {
    condition     = azurerm_backup_policy_vm.standard.backup[0].time == "23:00"
    error_message = "[UNIT] standard policy must run at 23:00 (off-peak)"
  }

  assert {
    condition     = azurerm_backup_policy_vm.standard.retention_daily[0].count == 30
    error_message = "[UNIT] standard daily retention must be 30 days"
  }

  assert {
    condition     = azurerm_backup_policy_vm.standard.retention_weekly[0].count == 12
    error_message = "[UNIT] standard weekly retention must be 12 weeks"
  }

  assert {
    condition     = azurerm_backup_policy_vm.standard.retention_monthly[0].count == 12
    error_message = "[UNIT] standard monthly retention must be 12 months"
  }

  assert {
    condition     = azurerm_backup_policy_vm.standard.retention_yearly[0].count == 3
    error_message = "[UNIT] standard yearly retention must be 3 years"
  }

  assert {
    condition     = azurerm_backup_policy_vm.standard.instant_restore_retention_days == 5
    error_message = "[UNIT] standard instant restore must be 5 days"
  }
}

###############################################################################
# MINITRUE-9418 – Enhanced policy V2 and hourly schedule
###############################################################################
run "unit_enhanced_policy_v2_hourly" {
  command = plan

  assert {
    condition     = azurerm_backup_policy_vm.enhanced.policy_type == "V2"
    error_message = "[UNIT] enhanced policy must be V2"
  }

  assert {
    condition     = azurerm_backup_policy_vm.enhanced.backup[0].frequency == "Hourly"
    error_message = "[UNIT] enhanced policy frequency must be Hourly"
  }

  assert {
    condition     = azurerm_backup_policy_vm.enhanced.backup[0].hour_interval == 4
    error_message = "[UNIT] enhanced policy interval must be 4 hours"
  }

  assert {
    condition     = azurerm_backup_policy_vm.enhanced.instant_restore_retention_days == 7
    error_message = "[UNIT] enhanced instant restore must be 7 days"
  }
}

###############################################################################
# MINITRUE-9416 – Disk snapshot vault and policies
###############################################################################
run "unit_disk_snapshot_vault" {
  command = plan

  assert {
    condition     = azurerm_data_protection_backup_vault.disk_vault.redundancy == "GeoRedundant"
    error_message = "[UNIT] disk vault must be GeoRedundant"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.disk_vault.datastore_type == "VaultStore"
    error_message = "[UNIT] disk vault datastore must be VaultStore"
  }

  assert {
    condition     = azurerm_data_protection_backup_policy_disk.os_disk.default_retention_duration == "P7D"
    error_message = "[UNIT] OS disk policy must retain for P7D"
  }

  assert {
    condition     = azurerm_data_protection_backup_policy_disk.data_disk.default_retention_duration == "P7D"
    error_message = "[UNIT] data disk policy must retain for P7D"
  }

  assert {
    condition     = contains(azurerm_data_protection_backup_policy_disk.os_disk.backup_repeating_time_intervals, "R/2024-01-01T02:00:00+00:00/PT4H")
    error_message = "[UNIT] OS disk policy must use PT4H repeating interval"
  }
}

###############################################################################
# MINITRUE-9414 – Automation account and runbooks
###############################################################################
run "unit_automation_account" {
  command = plan

  assert {
    condition     = azurerm_automation_account.backup_restore.name == "aa-minitrue-backup-restore"
    error_message = "[UNIT] automation account name must match expected value"
  }

  assert {
    condition     = azurerm_automation_account.backup_restore.identity[0].type == "SystemAssigned"
    error_message = "[UNIT] automation account must have SystemAssigned identity"
  }

  assert {
    condition     = azurerm_automation_account.backup_restore.sku_name == "Basic"
    error_message = "[UNIT] automation account SKU must be Basic"
  }
}

run "unit_restore_runbooks" {
  command = plan

  assert {
    condition     = azurerm_automation_runbook.full_vm_restore.name == "Invoke-FullVMRestore"
    error_message = "[UNIT] full VM restore runbook name"
  }

  assert {
    condition     = azurerm_automation_runbook.full_vm_restore.runbook_type == "PowerShell"
    error_message = "[UNIT] full VM restore runbook must be PowerShell"
  }

  assert {
    condition     = azurerm_automation_runbook.disk_restore.name == "Invoke-DiskRestore"
    error_message = "[UNIT] disk restore runbook name"
  }

  assert {
    condition     = azurerm_automation_runbook.file_level_recovery.name == "Invoke-FileLevelRecovery"
    error_message = "[UNIT] file-level recovery runbook name"
  }
}

run "unit_automation_rbac" {
  command = plan

  assert {
    condition     = azurerm_role_assignment.automation_backup_contributor.role_definition_name == "Backup Contributor"
    error_message = "[UNIT] automation account must have Backup Contributor role"
  }

  assert {
    condition     = azurerm_role_assignment.automation_vm_contributor.role_definition_name == "Virtual Machine Contributor"
    error_message = "[UNIT] automation account must have VM Contributor role"
  }
}

###############################################################################
# Sprint 3 – Monitoring and alerting
###############################################################################
run "unit_action_group" {
  command = plan

  assert {
    condition     = azurerm_monitor_action_group.backup_alerts.name == "ag-backup-failure-alerts"
    error_message = "[UNIT] action group name must be ag-backup-failure-alerts"
  }

  assert {
    condition     = length(azurerm_monitor_action_group.backup_alerts.email_receiver) == 1
    error_message = "[UNIT] action group must have one email receiver for the test email"
  }
}

run "unit_alert_rules" {
  command = plan

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.backup_job_failure.severity == 1
    error_message = "[UNIT] backup job failure alert severity must be 1 (Critical)"
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.backup_job_failure.enabled == true
    error_message = "[UNIT] backup job failure alert must be enabled"
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.backup_stale.severity == 2
    error_message = "[UNIT] stale backup alert severity must be 2 (Warning)"
  }

  assert {
    condition     = azurerm_monitor_metric_alert.vault_health.criteria[0].metric_name == "BackupHealthEvent"
    error_message = "[UNIT] vault health alert must target BackupHealthEvent metric"
  }
}

run "unit_law_created_when_empty" {
  command = plan

  assert {
    condition     = length(azurerm_log_analytics_workspace.backup) == 1
    error_message = "[UNIT] LAW must be created when log_analytics_workspace_id is empty"
  }

  assert {
    condition     = azurerm_log_analytics_workspace.backup[0].retention_in_days == 90
    error_message = "[UNIT] LAW retention must be 90 days"
  }
}

###############################################################################
# Tag consistency across all resources
###############################################################################
run "unit_tag_consistency" {
  command = plan

  assert {
    condition = (
      azurerm_recovery_services_vault.main.tags["Project"]      == "MINITRUE" &&
      azurerm_recovery_services_vault.main.tags["ManagedBy"]    == "Terraform" &&
      azurerm_recovery_services_vault.main.tags["Environment"]  == "test"
    )
    error_message = "[UNIT] RSV must carry all required tags"
  }
}
