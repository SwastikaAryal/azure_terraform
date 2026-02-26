###############################################################################
# tests/restore_testing.tftest.hcl
#
# Native Terraform test for MINITRUE-9414:
#   – Automation Account creation and managed identity
#   – Restore runbooks: FullVMRestore, DiskRestore, FileLevelRecovery
#   – RBAC role assignments (Backup Contributor, VM Contributor)
#
# Run:  terraform test -filter=tests/restore_testing.tftest.hcl
###############################################################################

variables {
  location                     = "eastus"
  secondary_location           = "westus"
  resource_group_name          = "rg-minitrue-test"
  environment                  = "test"
  vault_name                   = "rsv-minitrue-9414-test"
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
# Run 1 – Automation Account: name, location, SKU
###############################################################################
run "automation_account_properties" {
  command = plan

  assert {
    condition     = azurerm_automation_account.backup_restore.name == "aa-minitrue-backup-restore"
    error_message = "automation account name must be aa-minitrue-backup-restore (MINITRUE-9414)"
  }

  assert {
    condition     = azurerm_automation_account.backup_restore.location == var.location
    error_message = "automation account must be in the primary location"
  }

  assert {
    condition     = azurerm_automation_account.backup_restore.resource_group_name == var.resource_group_name
    error_message = "automation account must be in the configured resource group"
  }

  assert {
    condition     = azurerm_automation_account.backup_restore.sku_name == "Basic"
    error_message = "automation account SKU must be Basic"
  }
}

###############################################################################
# Run 2 – Automation Account: system-assigned managed identity
###############################################################################
run "automation_account_managed_identity" {
  command = plan

  assert {
    condition     = azurerm_automation_account.backup_restore.identity[0].type == "SystemAssigned"
    error_message = "automation account must have SystemAssigned identity to trigger restore jobs (MINITRUE-9414)"
  }
}

###############################################################################
# Run 3 – Automation Account output
###############################################################################
run "automation_account_output" {
  command = plan

  assert {
    condition     = output.automation_account_name == "aa-minitrue-backup-restore"
    error_message = "automation_account_name output must match the provisioned resource (MINITRUE-9414)"
  }
}

###############################################################################
# Run 4 – Full VM Restore runbook exists and is PowerShell
###############################################################################
run "full_vm_restore_runbook" {
  command = plan

  assert {
    condition     = azurerm_automation_runbook.full_vm_restore.name == "Invoke-FullVMRestore"
    error_message = "full VM restore runbook must be named Invoke-FullVMRestore (MINITRUE-9414 Task 1 & 2)"
  }

  assert {
    condition     = azurerm_automation_runbook.full_vm_restore.runbook_type == "PowerShell"
    error_message = "full VM restore runbook must be PowerShell type"
  }

  assert {
    condition     = azurerm_automation_runbook.full_vm_restore.log_verbose == true
    error_message = "full VM restore runbook must enable verbose logging for audit trail"
  }

  assert {
    condition     = azurerm_automation_runbook.full_vm_restore.log_progress == true
    error_message = "full VM restore runbook must enable progress logging"
  }

  assert {
    condition     = azurerm_automation_runbook.full_vm_restore.automation_account_name == azurerm_automation_account.backup_restore.name
    error_message = "runbook must be associated with the backup_restore automation account"
  }
}

###############################################################################
# Run 5 – Disk Restore runbook exists
###############################################################################
run "disk_restore_runbook" {
  command = plan

  assert {
    condition     = azurerm_automation_runbook.disk_restore.name == "Invoke-DiskRestore"
    error_message = "disk restore runbook must be named Invoke-DiskRestore (MINITRUE-9414 Task 3)"
  }

  assert {
    condition     = azurerm_automation_runbook.disk_restore.runbook_type == "PowerShell"
    error_message = "disk restore runbook must be PowerShell type"
  }
}

###############################################################################
# Run 6 – File-level recovery runbook exists
###############################################################################
run "file_level_recovery_runbook" {
  command = plan

  assert {
    condition     = azurerm_automation_runbook.file_level_recovery.name == "Invoke-FileLevelRecovery"
    error_message = "file-level recovery runbook must be named Invoke-FileLevelRecovery (MINITRUE-9414 Task 4)"
  }

  assert {
    condition     = azurerm_automation_runbook.file_level_recovery.runbook_type == "PowerShell"
    error_message = "file-level recovery runbook must be PowerShell type"
  }
}

###############################################################################
# Run 7 – Runbook content is non-empty (has actual PowerShell)
###############################################################################
run "runbooks_have_content" {
  command = plan

  assert {
    condition     = length(azurerm_automation_runbook.full_vm_restore.content) > 100
    error_message = "full VM restore runbook content must not be empty (MINITRUE-9414)"
  }

  assert {
    condition     = length(azurerm_automation_runbook.disk_restore.content) > 100
    error_message = "disk restore runbook content must not be empty"
  }

  assert {
    condition     = length(azurerm_automation_runbook.file_level_recovery.content) > 100
    error_message = "file-level recovery runbook content must not be empty"
  }
}

###############################################################################
# Run 8 – RBAC: Backup Contributor on the vault
###############################################################################
run "automation_backup_contributor_role" {
  command = plan

  assert {
    condition     = azurerm_role_assignment.automation_backup_contributor.role_definition_name == "Backup Contributor"
    error_message = "automation account must have Backup Contributor on the vault (MINITRUE-9414)"
  }

  assert {
    condition     = azurerm_role_assignment.automation_backup_contributor.scope == azurerm_recovery_services_vault.main.id
    error_message = "Backup Contributor role must be scoped to the RSV"
  }
}

###############################################################################
# Run 9 – RBAC: Virtual Machine Contributor at subscription scope
###############################################################################
run "automation_vm_contributor_role" {
  command = plan

  assert {
    condition     = azurerm_role_assignment.automation_vm_contributor.role_definition_name == "Virtual Machine Contributor"
    error_message = "automation account must have Virtual Machine Contributor for restore VM creation (MINITRUE-9414)"
  }

  assert {
    condition     = can(regex("/subscriptions/", azurerm_role_assignment.automation_vm_contributor.scope))
    error_message = "VM Contributor role must be scoped at the subscription level"
  }
}

###############################################################################
# Run 10 – All runbooks share the same automation account
###############################################################################
run "runbooks_use_same_account" {
  command = plan

  assert {
    condition = (
      azurerm_automation_runbook.full_vm_restore.automation_account_name      == "aa-minitrue-backup-restore" &&
      azurerm_automation_runbook.disk_restore.automation_account_name         == "aa-minitrue-backup-restore" &&
      azurerm_automation_runbook.file_level_recovery.automation_account_name  == "aa-minitrue-backup-restore"
    )
    error_message = "all restore runbooks must belong to the same automation account (MINITRUE-9414)"
  }
}
