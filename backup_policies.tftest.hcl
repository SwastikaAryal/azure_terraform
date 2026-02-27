###############################################################################
# tests/backup_policies.tftest.hcl
###############################################################################

variables {
  location                     = "eastus"
  secondary_location           = "westus"
  resource_group_name          = "DefaultResourceGroup-EUS"
  environment                  = "test"
  vault_name                   = "rsv-minitrue-9418-test"
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
# Run 1 – Standard policy: name, frequency, and scheduling
###############################################################################
run "standard_policy_schedule" {
  command = plan

  assert {
    condition     = azurerm_backup_policy_vm.standard.name == "bkpol-standard-daily-30d"
    error_message = "standard policy name must be bkpol-standard-daily-30d (MINITRUE-9418)"
  }

  assert {
    condition     = azurerm_backup_policy_vm.standard.backup[0].frequency == "Daily"
    error_message = "standard policy must back up Daily (MINITRUE-9418)"
  }

  assert {
    condition     = azurerm_backup_policy_vm.standard.backup[0].time == "23:00"
    error_message = "standard policy must be scheduled at 23:00 (off-peak window)"
  }

  assert {
    condition     = azurerm_backup_policy_vm.standard.resource_group_name == var.resource_group_name
    error_message = "standard policy must be in the configured resource group"
  }

  assert {
    condition     = azurerm_backup_policy_vm.standard.recovery_vault_name == azurerm_recovery_services_vault.main.name
    error_message = "standard policy must be linked to the RSV"
  }
}

###############################################################################
# Run 2 – Standard retention tiers
###############################################################################
run "standard_policy_retention_tiers" {
  command = plan

  assert {
    condition     = azurerm_backup_policy_vm.standard.retention_daily[0].count == 30
    error_message = "daily retention must be 30 days"
  }

  assert {
    condition     = azurerm_backup_policy_vm.standard.retention_weekly[0].count == 12
    error_message = "weekly retention must be 12 weeks"
  }

  assert {
    condition     = contains(azurerm_backup_policy_vm.standard.retention_weekly[0].weekdays, "Sunday")
    error_message = "weekly retention must include Sunday"
  }

  assert {
    condition     = azurerm_backup_policy_vm.standard.retention_monthly[0].count == 12
    error_message = "monthly retention must be 12 months"
  }

  assert {
    condition     = azurerm_backup_policy_vm.standard.retention_yearly[0].count == 3
    error_message = "yearly retention must be 3 years"
  }
}

###############################################################################
# Run 3 – Instant restore window
###############################################################################
run "standard_policy_instant_restore" {
  command = plan

  assert {
    condition     = azurerm_backup_policy_vm.standard.instant_restore_retention_days == 5
    error_message = "instant restore must be 5 days"
  }
}

###############################################################################
# Run 4 – Enhanced policy schedule
###############################################################################
run "enhanced_policy_schedule" {
  command = plan

  assert {
    condition     = azurerm_backup_policy_vm.enhanced.policy_type == "V2"
    error_message = "enhanced policy must be V2"
  }

  assert {
    condition     = azurerm_backup_policy_vm.enhanced.backup[0].frequency == "Hourly"
    error_message = "enhanced policy must use Hourly frequency"
  }

  assert {
    condition     = azurerm_backup_policy_vm.enhanced.backup[0].hour_interval == 4
    error_message = "enhanced policy must run every 4 hours"
  }

  assert {
    condition     = azurerm_backup_policy_vm.enhanced.backup[0].hour_duration == 12
    error_message = "enhanced policy window must span 12 hours"
  }
}

###############################################################################
# Run 5 – Enhanced retention tiers
###############################################################################
run "enhanced_policy_retention_tiers" {
  command = plan

  assert {
    condition     = azurerm_backup_policy_vm.enhanced.retention_daily[0].count == 30
    error_message = "enhanced daily retention must be 30 days"
  }

  assert {
    condition     = azurerm_backup_policy_vm.enhanced.retention_yearly[0].count == 3
    error_message = "enhanced yearly retention must be 3 years"
  }

  assert {
    condition     = azurerm_backup_policy_vm.enhanced.instant_restore_retention_days == 7
    error_message = "enhanced instant restore must be 7 days"
  }
}

###############################################################################
# Run 6 – LUN exclusion
###############################################################################
run "disk_lun_exclusion_configured" {
  command = plan

  assert {
    condition     = length(azurerm_backup_protected_vm.app_vms_selective) == 0
    error_message = "no selective-disk instances should be planned with empty app_vm_ids"
  }
}

###############################################################################
# Run 7 – VM policy assignments (FIXED)
###############################################################################
run "vm_policy_assignments" {
  command = plan  

  assert {
    condition     = output.standard_backup_policy_id != ""
    error_message = "standard_backup_policy_id must be non-empty"
  }

  assert {
    condition     = output.enhanced_backup_policy_id != ""
    error_message = "enhanced_backup_policy_id must be non-empty"
  }

  assert {
    condition     = output.standard_backup_policy_id != output.enhanced_backup_policy_id
    error_message = "standard and enhanced policies must be distinct"
  }
}
