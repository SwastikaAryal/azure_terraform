###############################################################################
# tests/monitoring.tftest.hcl
#
# Native Terraform test for Sprint 3:
#   – Log Analytics Workspace creation (when no external workspace supplied)
#   – RSV diagnostic settings (all required log categories)
#   – Action Group and email receivers
#   – Scheduled query rule alerts: backup job failure, stale backups
#   – Metric alert: vault health
#   – Log Analytics saved searches
#   – Workbook creation
#
# Run:  terraform test -filter=tests/monitoring.tftest.hcl
###############################################################################

variables {
  location                     = "eastus"
  secondary_location           = "westus"
  resource_group_name          = "rg-minitrue-test"
  environment                  = "test"
  vault_name                   = "rsv-minitrue-sprint3-test"
  snapshot_resource_group_name = "rg-minitrue-snaps-test"
  alert_email_addresses        = ["ops-test@example.com", "oncall@example.com"]
  log_analytics_workspace_id   = ""
  log_analytics_workspace_name = "law-minitrue-test"
  app_vm_ids                   = []
  web_vm_ids                   = []
  app_vm_os_disk_ids           = []
  web_vm_os_disk_ids           = []
  app_vm_data_disk_ids         = []
  web_vm_data_disk_ids         = []
}

###############################################################################
# Run 1 – Log Analytics Workspace is auto-created when no ID supplied
###############################################################################
run "log_analytics_workspace_created" {
  command = plan

  assert {
    condition     = length(azurerm_log_analytics_workspace.backup) == 1
    error_message = "a Log Analytics Workspace must be created when log_analytics_workspace_id is empty (Sprint 3)"
  }

  assert {
    condition     = azurerm_log_analytics_workspace.backup[0].name == var.log_analytics_workspace_name
    error_message = "LAW name must match the log_analytics_workspace_name variable"
  }

  assert {
    condition     = azurerm_log_analytics_workspace.backup[0].sku == "PerGB2018"
    error_message = "LAW SKU must be PerGB2018"
  }

  assert {
    condition     = azurerm_log_analytics_workspace.backup[0].retention_in_days == 90
    error_message = "LAW retention must be 90 days for backup compliance history (Sprint 3)"
  }

  assert {
    condition     = output.log_analytics_workspace_id != ""
    error_message = "log_analytics_workspace_id output must not be empty (Sprint 3)"
  }
}

###############################################################################
# Run 2 – External LAW is used when workspace ID is provided (no create)
###############################################################################
run "external_law_is_reused" {
  command = plan

  variables {
    log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-shared/providers/Microsoft.OperationalInsights/workspaces/law-shared"
  }

  assert {
    condition     = length(azurerm_log_analytics_workspace.backup) == 0
    error_message = "no LAW should be created when log_analytics_workspace_id is supplied"
  }
}

###############################################################################
# Run 3 – Diagnostic settings: all required log categories are enabled
###############################################################################
run "vault_diagnostic_categories" {
  command = plan

  assert {
    condition = (
      contains([for l in azurerm_monitor_diagnostic_setting.vault_diagnostics.enabled_log : l.category], "AzureBackupReport") &&
      contains([for l in azurerm_monitor_diagnostic_setting.vault_diagnostics.enabled_log : l.category], "CoreAzureBackup") &&
      contains([for l in azurerm_monitor_diagnostic_setting.vault_diagnostics.enabled_log : l.category], "AddonAzureBackupJobs") &&
      contains([for l in azurerm_monitor_diagnostic_setting.vault_diagnostics.enabled_log : l.category], "AddonAzureBackupAlerts") &&
      contains([for l in azurerm_monitor_diagnostic_setting.vault_diagnostics.enabled_log : l.category], "AddonAzureBackupPolicy") &&
      contains([for l in azurerm_monitor_diagnostic_setting.vault_diagnostics.enabled_log : l.category], "AddonAzureBackupStorage") &&
      contains([for l in azurerm_monitor_diagnostic_setting.vault_diagnostics.enabled_log : l.category], "AddonAzureBackupProtectedInstance")
    )
    error_message = "all 7 required backup log categories must be enabled in diagnostic settings (Sprint 3)"
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.vault_diagnostics.target_resource_id == azurerm_recovery_services_vault.main.id
    error_message = "diagnostic setting must target the RSV"
  }
}

###############################################################################
# Run 4 – Action Group: name, short name, and email receivers
###############################################################################
run "action_group_properties" {
  command = plan

  assert {
    condition     = azurerm_monitor_action_group.backup_alerts.name == "ag-backup-failure-alerts"
    error_message = "action group name must be ag-backup-failure-alerts (Sprint 3)"
  }

  assert {
    condition     = azurerm_monitor_action_group.backup_alerts.short_name == "bkp-alerts"
    error_message = "action group short_name must be bkp-alerts"
  }

  assert {
    condition     = azurerm_monitor_action_group.backup_alerts.resource_group_name == var.resource_group_name
    error_message = "action group must be in the configured resource group"
  }

  assert {
    condition     = output.action_group_id != ""
    error_message = "action_group_id output must not be empty (Sprint 3)"
  }
}

###############################################################################
# Run 5 – Action Group: one email receiver per address in the variable
###############################################################################
run "action_group_email_receivers" {
  command = plan

  assert {
    condition     = length(azurerm_monitor_action_group.backup_alerts.email_receiver) == length(var.alert_email_addresses)
    error_message = "action group must create one email receiver per address in alert_email_addresses (Sprint 3)"
  }

  assert {
    condition = alltrue([
      for r in azurerm_monitor_action_group.backup_alerts.email_receiver : r.use_common_alert_schema == true
    ])
    error_message = "all email receivers must use the common alert schema"
  }
}

###############################################################################
# Run 6 – Backup job failure alert rule properties
###############################################################################
run "backup_job_failure_alert" {
  command = plan

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.backup_job_failure.name == "alert-backup-job-failure"
    error_message = "backup job failure alert name must be alert-backup-job-failure (Sprint 3)"
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.backup_job_failure.severity == 1
    error_message = "backup job failure alert must be severity 1 (Critical)"
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.backup_job_failure.enabled == true
    error_message = "backup job failure alert must be enabled"
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.backup_job_failure.evaluation_frequency == "PT15M"
    error_message = "backup job failure alert must evaluate every PT15M (15 minutes)"
  }

  assert {
    condition = contains(
      azurerm_monitor_scheduled_query_rules_alert_v2.backup_job_failure.action[0].action_groups,
      azurerm_monitor_action_group.backup_alerts.id
    )
    error_message = "backup job failure alert must trigger the backup_alerts action group"
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.backup_job_failure.criteria[0].operator == "GreaterThan"
    error_message = "backup job failure alert must fire when count is GreaterThan threshold"
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.backup_job_failure.criteria[0].threshold == 0
    error_message = "backup job failure alert threshold must be 0 (any failure triggers alert)"
  }
}

###############################################################################
# Run 7 – Stale backup alert (no backup in 24 hours)
###############################################################################
run "stale_backup_alert" {
  command = plan

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.backup_stale.name == "alert-backup-not-run-24h"
    error_message = "stale backup alert name must be alert-backup-not-run-24h (Sprint 3)"
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.backup_stale.severity == 2
    error_message = "stale backup alert must be severity 2 (Warning)"
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.backup_stale.window_duration == "P1D"
    error_message = "stale backup alert window_duration must be P1D (24 hours)"
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.backup_stale.evaluation_frequency == "PT1H"
    error_message = "stale backup alert must evaluate every PT1H (hourly)"
  }
}

###############################################################################
# Run 8 – Vault health metric alert
###############################################################################
run "vault_health_metric_alert" {
  command = plan

  assert {
    condition     = azurerm_monitor_metric_alert.vault_health.name == "alert-rsv-health"
    error_message = "vault health alert name must be alert-rsv-health (Sprint 3)"
  }

  assert {
    condition     = azurerm_monitor_metric_alert.vault_health.severity == 1
    error_message = "vault health metric alert must be severity 1 (Critical)"
  }

  assert {
    condition     = azurerm_monitor_metric_alert.vault_health.enabled == true
    error_message = "vault health metric alert must be enabled"
  }

  assert {
    condition     = azurerm_monitor_metric_alert.vault_health.criteria[0].metric_name == "BackupHealthEvent"
    error_message = "vault health alert must target the BackupHealthEvent metric"
  }

  assert {
    condition     = azurerm_monitor_metric_alert.vault_health.criteria[0].operator == "GreaterThan"
    error_message = "vault health alert operator must be GreaterThan"
  }

  assert {
    condition     = azurerm_monitor_metric_alert.vault_health.criteria[0].threshold == 0
    error_message = "vault health alert threshold must be 0 (any health event triggers)"
  }

  assert {
    condition     = contains(azurerm_monitor_metric_alert.vault_health.scopes, azurerm_recovery_services_vault.main.id)
    error_message = "vault health alert must be scoped to the RSV"
  }
}

###############################################################################
# Run 9 – Log Analytics saved searches exist (when LAW is auto-created)
###############################################################################
run "saved_searches_exist" {
  command = plan

  assert {
    condition     = length(azurerm_log_analytics_saved_search.backup_job_summary) == 1
    error_message = "BackupJobSummary saved search must be created (Sprint 3 Task 4)"
  }

  assert {
    condition     = length(azurerm_log_analytics_saved_search.backup_failure_details) == 1
    error_message = "BackupFailureDetails saved search must be created (Sprint 3 Task 4)"
  }

  assert {
    condition     = length(azurerm_log_analytics_saved_search.backup_compliance_report) == 1
    error_message = "BackupComplianceReport saved search must be created (Sprint 3 Task 4)"
  }

  assert {
    condition     = length(azurerm_log_analytics_saved_search.backup_storage_usage) == 1
    error_message = "BackupStorageUsage saved search must be created (Sprint 3 Task 4)"
  }
}

###############################################################################
# Run 10 – Governance workbook is created
###############################################################################
run "governance_workbook_exists" {
  command = plan

  assert {
    condition     = length(azurerm_application_insights_workbook.backup_dashboard) == 1
    error_message = "MINITRUE backup governance workbook must be created (Sprint 3 Task 5)"
  }

  assert {
    condition     = azurerm_application_insights_workbook.backup_dashboard[0].display_name == "MINITRUE Backup Governance Dashboard"
    error_message = "workbook display name must be 'MINITRUE Backup Governance Dashboard'"
  }
}

###############################################################################
# Run 11 – No LAW resources when workspace ID is pre-supplied
###############################################################################
run "no_law_resources_when_external" {
  command = plan

  variables {
    log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-shared/providers/Microsoft.OperationalInsights/workspaces/law-shared"
  }

  assert {
    condition     = length(azurerm_log_analytics_saved_search.backup_job_summary) == 0
    error_message = "no saved searches should be created when an external LAW is provided"
  }

  assert {
    condition     = length(azurerm_application_insights_workbook.backup_dashboard) == 0
    error_message = "no workbook should be created when an external LAW is provided"
  }
}
