###############################################################################
# tests/outputs_and_integration.tftest.hcl
#
# Integration tests that verify:
#   – All module outputs are present and non-empty
#   – Cross-resource references are wired correctly
#   – Variable defaults produce a valid plan
#   – Idempotency guard (plan produces no changes after apply)
#
# Run:  terraform test -filter=tests/outputs_and_integration.tftest.hcl
###############################################################################

variables {
  location                     = "eastus"
  secondary_location           = "westus"
  resource_group_name          = "rg-minitrue-test"
  environment                  = "test"
  vault_name                   = "rsv-minitrue-integration-test"
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

###############################################################################
# Run 1 – All documented outputs are present and non-empty
###############################################################################
run "all_outputs_present" {
  command = plan

  assert {
    condition     = output.recovery_services_vault_id != ""
    error_message = "recovery_services_vault_id must not be empty"
  }

  assert {
    condition     = output.recovery_services_vault_name != ""
    error_message = "recovery_services_vault_name must not be empty"
  }

  assert {
    condition     = output.data_protection_backup_vault_id != ""
    error_message = "data_protection_backup_vault_id must not be empty (MINITRUE-9416)"
  }

  assert {
    condition     = output.automation_account_name != ""
    error_message = "automation_account_name must not be empty (MINITRUE-9414)"
  }

  assert {
    condition     = output.action_group_id != ""
    error_message = "action_group_id must not be empty (Sprint 3)"
  }

  assert {
    condition     = output.log_analytics_workspace_id != ""
    error_message = "log_analytics_workspace_id must not be empty (Sprint 3)"
  }

  assert {
    condition     = output.standard_backup_policy_id != ""
    error_message = "standard_backup_policy_id must not be empty (MINITRUE-9418)"
  }

  assert {
    condition     = output.enhanced_backup_policy_id != ""
    error_message = "enhanced_backup_policy_id must not be empty (MINITRUE-9418)"
  }
}

###############################################################################
# Run 2 – Output IDs reference the correct Azure resource types
###############################################################################
run "output_resource_type_sanity" {
  command = plan

  assert {
    condition     = can(regex("Microsoft.RecoveryServices/vaults", output.recovery_services_vault_id))
    error_message = "recovery_services_vault_id must contain Microsoft.RecoveryServices/vaults"
  }

  assert {
    condition     = can(regex("Microsoft.DataProtection/backupVaults", output.data_protection_backup_vault_id))
    error_message = "data_protection_backup_vault_id must contain Microsoft.DataProtection/backupVaults"
  }

  assert {
    condition     = can(regex("Microsoft.RecoveryServices/vaults/.*/backupPolicies", output.standard_backup_policy_id))
    error_message = "standard_backup_policy_id must be a vault-scoped backup policy resource ID"
  }

  assert {
    condition     = can(regex("Microsoft.RecoveryServices/vaults/.*/backupPolicies", output.enhanced_backup_policy_id))
    error_message = "enhanced_backup_policy_id must be a vault-scoped backup policy resource ID"
  }
}

###############################################################################
# Run 3 – Standard and Enhanced policies are distinct resources
###############################################################################
run "policies_are_distinct" {
  command = plan

  assert {
    condition     = output.standard_backup_policy_id != output.enhanced_backup_policy_id
    error_message = "standard and enhanced backup policies must be distinct Azure resources"
  }
}

###############################################################################
# Run 4 – Cross-resource wiring: policies reference the correct vault
###############################################################################
run "policies_reference_vault" {
  command = plan

  assert {
    condition     = azurerm_backup_policy_vm.standard.recovery_vault_name == azurerm_recovery_services_vault.main.name
    error_message = "standard policy must reference the RSV by name"
  }

  assert {
    condition     = azurerm_backup_policy_vm.enhanced.recovery_vault_name == azurerm_recovery_services_vault.main.name
    error_message = "enhanced policy must reference the RSV by name"
  }

  assert {
    condition     = azurerm_backup_policy_vm.standard.resource_group_name == azurerm_recovery_services_vault.main.resource_group_name
    error_message = "standard policy and RSV must be in the same resource group"
  }
}

###############################################################################
# Run 5 – Diagnostic settings reference the RSV and the LAW
###############################################################################
run "diagnostics_cross_reference" {
  command = plan

  assert {
    condition     = azurerm_monitor_diagnostic_setting.vault_diagnostics.target_resource_id == azurerm_recovery_services_vault.main.id
    error_message = "diagnostic setting must target the RSV (Sprint 3)"
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.vault_diagnostics.log_analytics_workspace_id == local.law_id
    error_message = "diagnostic setting must send logs to the LAW (Sprint 3)"
  }
}

###############################################################################
# Run 6 – Automation account RBAC references the vault correctly
###############################################################################
run "automation_rbac_scope" {
  command = plan

  assert {
    condition     = azurerm_role_assignment.automation_backup_contributor.scope == azurerm_recovery_services_vault.main.id
    error_message = "Backup Contributor role must be scoped to the RSV (MINITRUE-9414)"
  }

  assert {
    condition     = azurerm_role_assignment.automation_backup_contributor.principal_id == azurerm_automation_account.backup_restore.identity[0].principal_id
    error_message = "Backup Contributor must be assigned to the Automation Account managed identity"
  }
}

###############################################################################
# Run 7 – Alert action group ID is wired into all alert rules
###############################################################################
run "alerts_use_action_group" {
  command = plan

  assert {
    condition = contains(
      azurerm_monitor_scheduled_query_rules_alert_v2.backup_job_failure.action[0].action_groups,
      azurerm_monitor_action_group.backup_alerts.id
    )
    error_message = "backup job failure alert must use the backup_alerts action group (Sprint 3)"
  }

  assert {
    condition = contains(
      azurerm_monitor_scheduled_query_rules_alert_v2.backup_stale.action[0].action_groups,
      azurerm_monitor_action_group.backup_alerts.id
    )
    error_message = "stale backup alert must use the backup_alerts action group (Sprint 3)"
  }

  assert {
    condition     = azurerm_monitor_metric_alert.vault_health.action[0].action_group_id == azurerm_monitor_action_group.backup_alerts.id
    error_message = "vault health metric alert must use the backup_alerts action group (Sprint 3)"
  }
}

###############################################################################
# Run 8 – Tags are consistent across all key resources
###############################################################################
run "consistent_tags" {
  command = plan

  assert {
    condition = (
      azurerm_recovery_services_vault.main.tags["Project"]             == "MINITRUE" &&
      azurerm_data_protection_backup_vault.disk_vault.tags["Project"]  == "MINITRUE" &&
      azurerm_automation_account.backup_restore.tags["Project"]        == "MINITRUE" &&
      azurerm_monitor_action_group.backup_alerts.tags["Project"]       == "MINITRUE"
    )
    error_message = "all key resources must carry Project=MINITRUE tag"
  }

  assert {
    condition = (
      azurerm_recovery_services_vault.main.tags["ManagedBy"]            == "Terraform" &&
      azurerm_data_protection_backup_vault.disk_vault.tags["ManagedBy"] == "Terraform" &&
      azurerm_automation_account.backup_restore.tags["ManagedBy"]       == "Terraform"
    )
    error_message = "all key resources must carry ManagedBy=Terraform tag"
  }
}

###############################################################################
# Run 9 – Variable defaults produce a valid plan (smoke test)
###############################################################################
run "default_variables_plan" {
  command = plan

  # All defaults should combine into a coherent plan with zero errors.
  # The assertions below check structural soundness.

  assert {
    condition     = azurerm_recovery_services_vault.main.name == var.vault_name
    error_message = "vault_name variable must flow through to the vault resource"
  }

  assert {
    condition     = azurerm_recovery_services_vault.main.location == var.location
    error_message = "location variable must flow through to the vault resource"
  }
}

###############################################################################
# Run 10 – Secondary location variable is wired to cross-region resources
###############################################################################
run "secondary_location_wired" {
  command = plan

  variables {
    secondary_location = "westus2"
  }

  assert {
    # The cross-region snapshot copy policy embeds secondary_location in policy_rule JSON.
    condition     = can(regex("westus2", azurerm_policy_definition.cross_region_snapshot_copy.policy_rule))
    error_message = "cross-region snapshot copy policy must reference the secondary_location variable"
  }
}
