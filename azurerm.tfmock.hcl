###############################################################################
# tests/mocks/azurerm.tfmock.hcl
#
# Mock provider for azurerm that lets all tests run as pure unit tests
# (terraform test -filter=... will use this when AZURE credentials are absent).
#
# Usage (in any .tftest.hcl file):
#
#   mock_provider "azurerm" {
#     mock_data   "azurerm_client_config" { defaults = { ... } }
#   }
#
# Or reference this file directly in a run block:
#
#   provider_mock_data {
#     source = "./tests/mocks/azurerm.tfmock.hcl"
#   }
#
###############################################################################

mock_provider "azurerm" {
  alias = "mock"

  # ── azurerm_client_config ────────────────────────────────────────────────
  mock_data "azurerm_client_config" {
    defaults = {
      client_id       = "00000000-0000-0000-0000-000000000001"
      tenant_id       = "00000000-0000-0000-0000-000000000002"
      subscription_id = "00000000-0000-0000-0000-000000000003"
      object_id       = "00000000-0000-0000-0000-000000000004"
    }
  }

  # ── Recovery Services Vault ───────────────────────────────────────────────
  mock_resource "azurerm_recovery_services_vault" {
    defaults = {
      id                           = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-minitrue-test/providers/Microsoft.RecoveryServices/vaults/rsv-minitrue-test"
      sku                          = "Standard"
      soft_delete_enabled          = true
      cross_region_restore_enabled = true
      storage_mode_type            = "GeoRedundant"
      immutability                 = "Unlocked"
    }
  }

  # ── VM Backup Policy ──────────────────────────────────────────────────────
  mock_resource "azurerm_backup_policy_vm" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-minitrue-test/providers/Microsoft.RecoveryServices/vaults/rsv-minitrue-test/backupPolicies/mock-policy"
    }
  }

  # ── Protected VM (app) ────────────────────────────────────────────────────
  mock_resource "azurerm_backup_protected_vm" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-minitrue-test/providers/Microsoft.RecoveryServices/vaults/rsv-minitrue-test/backupFabrics/Azure/protectionContainers/iaasvmcontainer/protectedItems/mock-vm"
    }
  }

  # ── Data Protection Backup Vault ─────────────────────────────────────────
  mock_resource "azurerm_data_protection_backup_vault" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-minitrue-test/providers/Microsoft.DataProtection/backupVaults/dpbv-minitrue-disk-snapshots"
      identity = [{
        type         = "SystemAssigned"
        principal_id = "00000000-0000-0000-0000-000000000010"
        tenant_id    = "00000000-0000-0000-0000-000000000002"
      }]
    }
  }

  # ── Disk Backup Policy ────────────────────────────────────────────────────
  mock_resource "azurerm_data_protection_backup_policy_disk" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-minitrue-test/providers/Microsoft.DataProtection/backupVaults/dpbv-minitrue-disk-snapshots/backupPolicies/mock-disk-policy"
    }
  }

  # ── Disk Backup Instance ──────────────────────────────────────────────────
  mock_resource "azurerm_data_protection_backup_instance_disk" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-minitrue-test/providers/Microsoft.DataProtection/backupVaults/dpbv-minitrue-disk-snapshots/backupInstances/mock-instance"
    }
  }

  # ── Automation Account ────────────────────────────────────────────────────
  mock_resource "azurerm_automation_account" {
    defaults = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-minitrue-test/providers/Microsoft.Automation/automationAccounts/aa-minitrue-backup-restore"
      identity = [{
        type         = "SystemAssigned"
        principal_id = "00000000-0000-0000-0000-000000000020"
        tenant_id    = "00000000-0000-0000-0000-000000000002"
      }]
    }
  }

  # ── Automation Runbook ────────────────────────────────────────────────────
  mock_resource "azurerm_automation_runbook" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-minitrue-test/providers/Microsoft.Automation/automationAccounts/aa-minitrue-backup-restore/runbooks/mock-runbook"
    }
  }

  # ── Role Assignment ───────────────────────────────────────────────────────
  mock_resource "azurerm_role_assignment" {
    defaults = {
      id                   = "/subscriptions/00000000-0000-0000-0000-000000000003/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000099"
      principal_type       = "ServicePrincipal"
      role_definition_id   = "/subscriptions/00000000-0000-0000-0000-000000000003/providers/Microsoft.Authorization/roleDefinitions/mock-role-def-id"
    }
  }

  # ── Log Analytics Workspace ───────────────────────────────────────────────
  mock_resource "azurerm_log_analytics_workspace" {
    defaults = {
      id                  = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-minitrue-test/providers/Microsoft.OperationalInsights/workspaces/law-minitrue-test"
      workspace_id        = "00000000-0000-0000-0000-000000000030"
      primary_shared_key  = "mock-primary-key=="
      secondary_shared_key = "mock-secondary-key=="
    }
  }

  # ── Monitor Diagnostic Setting ────────────────────────────────────────────
  mock_resource "azurerm_monitor_diagnostic_setting" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-minitrue-test/providers/Microsoft.RecoveryServices/vaults/rsv-minitrue-test|diag-rsv-to-law"
    }
  }

  # ── Monitor Action Group ──────────────────────────────────────────────────
  mock_resource "azurerm_monitor_action_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-minitrue-test/providers/Microsoft.Insights/actionGroups/ag-backup-failure-alerts"
    }
  }

  # ── Scheduled Query Rules Alert v2 ────────────────────────────────────────
  mock_resource "azurerm_monitor_scheduled_query_rules_alert_v2" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-minitrue-test/providers/Microsoft.Insights/scheduledQueryRules/mock-alert"
    }
  }

  # ── Metric Alert ──────────────────────────────────────────────────────────
  mock_resource "azurerm_monitor_metric_alert" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-minitrue-test/providers/Microsoft.Insights/metricAlerts/alert-rsv-health"
    }
  }

  # ── Log Analytics Saved Search ────────────────────────────────────────────
  mock_resource "azurerm_log_analytics_saved_search" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-minitrue-test/providers/Microsoft.OperationalInsights/workspaces/law-minitrue-test/savedSearches/mock-search"
    }
  }

  # ── Application Insights Workbook ─────────────────────────────────────────
  mock_resource "azurerm_application_insights_workbook" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-minitrue-test/providers/Microsoft.Insights/workbooks/mock-workbook"
    }
  }

  # ── Policy Definition ─────────────────────────────────────────────────────
  mock_resource "azurerm_policy_definition" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/providers/Microsoft.Authorization/policyDefinitions/mock-policy"
    }
  }

  # ── Subscription Policy Assignment ────────────────────────────────────────
  mock_resource "azurerm_subscription_policy_assignment" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/providers/Microsoft.Authorization/policyAssignments/mock-assignment"
      identity = [{
        type         = "SystemAssigned"
        principal_id = "00000000-0000-0000-0000-000000000050"
        tenant_id    = "00000000-0000-0000-0000-000000000002"
      }]
    }
  }
}
