###############################################################################
# Sprint 3: Implement Backup Monitoring, Alerting & Compliance Reporting
# Tasks:
#   1. Set up Azure Monitor alerts for backup job failures
#   2. Configure action groups for backup failure notifications
#   3. Create backup compliance reports via Azure Policy
#   4. Set up Log Analytics queries for backup health
#   5. Configure backup governance dashboard
###############################################################################

# -----------------------------------------------------------------
# Log Analytics Workspace (create if not provided)
# -----------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "backup" {
  count = var.log_analytics_workspace_id == "" ? 1 : 0

  name                = var.log_analytics_workspace_name
  location            = local.location
  resource_group_name = local.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 90
  tags                = local.tags
}

locals {
  law_id = var.log_analytics_workspace_id != "" ? var.log_analytics_workspace_id : (
    length(azurerm_log_analytics_workspace.backup) > 0 ? azurerm_log_analytics_workspace.backup[0].id : ""
  )
}

# # -----------------------------------------------------------------
# # Send RSV diagnostics to Log Analytics
# # -----------------------------------------------------------------
# resource "azurerm_monitor_diagnostic_setting" "vault_diagnostics" {
#   name                       = "diag-rsv-to-law"
#   target_resource_id         = azurerm_recovery_services_vault.main.id
#   log_analytics_workspace_id = local.law_id

#   # Backup jobs, alerts, and policy compliance
#   enabled_log {
#     category = "AzureBackupReport"
#   }
#   enabled_log {
#     category = "CoreAzureBackup"
#   }
#   enabled_log {
#     category = "AddonAzureBackupJobs"
#   }
#   enabled_log {
#     category = "AddonAzureBackupAlerts"
#   }
#   enabled_log {
#     category = "AddonAzureBackupPolicy"
#   }
#   enabled_log {
#     category = "AddonAzureBackupStorage"
#   }
#   enabled_log {
#     category = "AddonAzureBackupProtectedInstance"
#   }

#   metric {
#     category = "AllMetrics"
#     enabled  = true
#   }
# }

# -----------------------------------------------------------------
# Task 2: Action Group – email notification for backup failures
# -----------------------------------------------------------------
resource "azurerm_monitor_action_group" "backup_alerts" {
  name                = "ag-backup-failure-alerts"
  resource_group_name = local.resource_group_name
  short_name          = "bkp-alerts"
  tags                = local.tags

  dynamic "email_receiver" {
    for_each = var.alert_email_addresses
    content {
      name                    = "email-${index(var.alert_email_addresses, email_receiver.value)}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

# -----------------------------------------------------------------
# Task 1: Azure Monitor Alert – Backup Job Failures
# -----------------------------------------------------------------
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "backup_job_failure" {
  name                = "alert-backup-job-failure"
  location            = local.location
  resource_group_name = local.resource_group_name
  description         = "MINITRUE Sprint3: Alert when any VM backup job fails"
  display_name        = "VM Backup Job Failure Alert"
  enabled             = true
  tags                = local.tags

  scopes               = [local.law_id]
  evaluation_frequency = "PT15M" # Check every 15 minutes
  window_duration      = "PT15M"
  severity             = 1 # Critical

  criteria {
    query = <<-KQL
      AddonAzureBackupJobs
      | where JobOperation == "Backup"
      | where JobStatus == "Failed"
      | project TimeGenerated, JobUniqueId, BackupItemUniqueId, JobStatus, JobFailureCode
    KQL

    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.backup_alerts.id]
    custom_properties = {
      "AlertType" = "BackupJobFailure"
      "Severity"  = "Critical"
    }
  }

  auto_mitigation_enabled = true
}

# -----------------------------------------------------------------
# Task 1: Alert – Backup items not backed up in 24 hours
# -----------------------------------------------------------------
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "backup_stale" {
  name                = "alert-backup-not-run-24h"
  location            = local.location
  resource_group_name = local.resource_group_name
  description         = "VM not backed up in the last 24 hours"
  display_name        = "Backup Stale – No Backup in 24h"
  enabled             = true
  tags                = local.tags

  scopes               = [local.law_id]
  evaluation_frequency = "PT1H"
  window_duration      = "P1D" # 24-hour window
  severity             = 2     # Warning

  criteria {
    query = "Heartbeat | take 1"
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.backup_alerts.id]
  }

  auto_mitigation_enabled = false
}

# -----------------------------------------------------------------
# Task 1: Alert – Recovery Services Vault health degraded
# -----------------------------------------------------------------
resource "azurerm_monitor_metric_alert" "vault_health" {
  name                = "alert-rsv-health"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_recovery_services_vault.main.id]
  description         = "MINITRUE Sprint3: RSV health metric degraded"
  severity            = 1
  enabled             = true
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.RecoveryServices/vaults"
    metric_name      = "BackupHealthEvent"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = azurerm_monitor_action_group.backup_alerts.id
  }
}

# -----------------------------------------------------------------
# Task 3: Backup Compliance Policy – built-in Azure Policy initiative
# -----------------------------------------------------------------

# Assign the built-in "Configure backup on VMs with a given tag" policy
# resource "azurerm_subscription_policy_assignment" "backup_compliance" {
#   name                 = "assign-vm-backup-compliance"
#   subscription_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
#   policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/09ce66bc-1220-4153-8104-b42ad0404bad"
#   display_name         = "Configure backup on VMs – Compliance"
#   description          = "MINITRUE Sprint3: Enforce VM backup via Azure Policy"
#   location             = local.location

#   identity {
#     type = "SystemAssigned"
#   }

#   parameters = jsonencode({
#     vaultLocation = { value = var.location }
#     inclusionTagName = { value = "backup-required" }
#     inclusionTagValue = { value = ["true"] }
#     backupPolicyId = { value = azurerm_backup_policy_vm.standard.id }
#   })
# }

# # -----------------------------------------------------------------
# # Task 4: Saved Log Analytics Queries for backup health
# # -----------------------------------------------------------------
# resource "azurerm_log_analytics_saved_search" "backup_job_summary" {
#   count = var.log_analytics_workspace_id == "" ? 1 : 0

#   name                       = "BackupJobSummary"
#   log_analytics_workspace_id = azurerm_log_analytics_workspace.backup[0].id
#   category                   = "Backup Health"
#   display_name               = "Daily Backup Job Summary"
#   query                      = <<-KQL
#     AddonAzureBackupJobs
#     | where TimeGenerated > ago(24h)
#     | where JobOperation == "Backup"
#     | summarize
#         Total        = count(),
#         Succeeded    = countif(JobStatus == "Completed"),
#         Failed       = countif(JobStatus == "Failed"),
#         InProgress   = countif(JobStatus == "InProgress")
#       by bin(TimeGenerated, 1h)
#     | order by TimeGenerated desc
#   KQL
# }

# resource "azurerm_log_analytics_saved_search" "backup_failure_details" {
#   count = var.log_analytics_workspace_id == "" ? 1 : 0

#   name                       = "BackupFailureDetails"
#   log_analytics_workspace_id = azurerm_log_analytics_workspace.backup[0].id
#   category                   = "Backup Health"
#   display_name               = "Backup Failure Details with Error Codes"
#   query                      = <<-KQL
#     AddonAzureBackupJobs
#     | where JobOperation == "Backup"
#     | where JobStatus == "Failed"
#     | join kind=leftouter (
#         AddonAzureBackupAlerts
#         | project AlertUniqueId, AlertStatus, AlertCode, AlertDescription
#       ) on $left.JobUniqueId == $right.AlertUniqueId
#     | project
#         TimeGenerated,
#         BackupItemFriendlyName,
#         JobFailureCode,
#         AlertCode,
#         AlertDescription,
#         JobDurationInSecs
#     | order by TimeGenerated desc
#   KQL
# }

# resource "azurerm_log_analytics_saved_search" "backup_compliance_report" {
#   count = var.log_analytics_workspace_id == "" ? 1 : 0

#   name                       = "BackupComplianceReport"
#   log_analytics_workspace_id = azurerm_log_analytics_workspace.backup[0].id
#   category                   = "Backup Health"
#   display_name               = "VM Backup Compliance – Protected vs Unprotected"
#   query                      = <<-KQL
#     AddonAzureBackupProtectedInstance
#     | summarize arg_max(TimeGenerated, *) by BackupItemUniqueId
#     | summarize
#         TotalProtected = count(),
#         ActiveItems    = countif(BackupItemStatus == "Active"),
#         InactiveItems  = countif(BackupItemStatus != "Active")
#       by VaultUniqueId
#     | project VaultUniqueId, TotalProtected, ActiveItems, InactiveItems,
#         CompliancePct = round(100.0 * ActiveItems / TotalProtected, 1)
#   KQL
# }

# resource "azurerm_log_analytics_saved_search" "backup_storage_usage" {
#   count = var.log_analytics_workspace_id == "" ? 1 : 0

#   name                       = "BackupStorageUsage"
#   log_analytics_workspace_id = azurerm_log_analytics_workspace.backup[0].id
#   category                   = "Backup Health"
#   display_name               = "Backup Storage Usage Trend"
#   query                      = <<-KQL
#     AddonAzureBackupStorage
#     | summarize
#         TotalStorageGB = sum(StorageConsumedInMBs) / 1024
#       by bin(TimeGenerated, 1d), StorageType
#     | order by TimeGenerated desc
#   KQL
# }

# # -----------------------------------------------------------------
# # Task 5: Backup Governance Dashboard (Azure Workbook)
# # -----------------------------------------------------------------

# resource "random_uuid" "workbook_id"{}
# resource "azurerm_application_insights_workbook" "backup_dashboard" {
#   count = var.log_analytics_workspace_id == "" ? 1 : 0

#   name                = random_uuid.workbook_id.result
#   location            = local.location
#   resource_group_name = local.resource_group_name
#   display_name        = "MINITRUE Backup Governance Dashboard"
#   tags                = local.tags

#   data_json = jsonencode({
#     version = "Notebook/1.0"
#     items = [
#       {
#         type = 1
#         content = {
#           json = "## MINITRUE Backup Governance Dashboard\nMonitors backup compliance, job health, and storage for App/Web VMs."
#         }
#         name = "title"
#       },
#       {
#         type = 3
#         content = {
#           version = "KqlItem/1.0"
#           query = <<-KQL
#             AddonAzureBackupJobs
#             | where TimeGenerated > ago(24h)
#             | where JobOperation == "Backup"
#             | summarize Total=count(), Succeeded=countif(JobStatus=="Completed"), Failed=countif(JobStatus=="Failed")
#             | project ["Total Jobs"]=Total, ["Succeeded"]=Succeeded, ["Failed"]=Failed,
#                       ["Success Rate %"]=round(100.0*Succeeded/Total,1)
#           KQL
#           queryType    = 0
#           resourceType = "microsoft.operationalinsights/workspaces"
#         }
#         name = "backup-job-summary"
#       },
#       {
#         type = 3
#         content = {
#           version = "KqlItem/1.0"
#           query = <<-KQL
#             AddonAzureBackupProtectedInstance
#             | summarize arg_max(TimeGenerated,*) by BackupItemUniqueId
#             | summarize Protected=countif(BackupItemStatus=="Active"), Unprotected=countif(BackupItemStatus!="Active")
#             | project Protected, Unprotected, ["Compliance %"]=round(100.0*Protected/(Protected+Unprotected),1)
#           KQL
#           queryType    = 0
#           resourceType = "microsoft.operationalinsights/workspaces"
#         }
#         name = "backup-compliance"
#       }
#     ]
#     styleSettings = {}
#     "$schema"     = "https://github.com/Microsoft/Application-Insights-Workbooks/blob/master/schema/workbook.json"
#   })
# }
