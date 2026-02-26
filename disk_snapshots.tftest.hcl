###############################################################################
# tests/disk_snapshots.tftest.hcl
#
# Native Terraform test for MINITRUE-9416:
#   – Data Protection Backup Vault (disk snapshot vault)
#   – OS disk snapshot policy (4-hour intervals, 7-day retention)
#   – Data disk snapshot policy (daily, 7-day retention)
#   – Weekly vault-tier retention rule (4 weeks)
#   – Cross-region snapshot copy Azure Policy
#   – Snapshot cleanup Azure Policy
#
# Run:  terraform test -filter=tests/disk_snapshots.tftest.hcl
###############################################################################

variables {
  location                     = "eastus"
  secondary_location           = "westus"
  resource_group_name          = "rg-minitrue-test"
  environment                  = "test"
  vault_name                   = "rsv-minitrue-9416-test"
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
# Run 1 – Data Protection Backup Vault properties
###############################################################################
run "disk_vault_properties" {
  command = plan

  assert {
    condition     = azurerm_data_protection_backup_vault.disk_vault.name == "dpbv-minitrue-disk-snapshots"
    error_message = "disk vault name must be dpbv-minitrue-disk-snapshots (MINITRUE-9416)"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.disk_vault.datastore_type == "VaultStore"
    error_message = "disk vault datastore_type must be VaultStore (MINITRUE-9416)"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.disk_vault.redundancy == "GeoRedundant"
    error_message = "disk vault must use GeoRedundant storage for DR (MINITRUE-9416)"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.disk_vault.resource_group_name == var.resource_group_name
    error_message = "disk vault must be in the primary resource group"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.disk_vault.location == var.location
    error_message = "disk vault must be in the primary location"
  }
}

###############################################################################
# Run 2 – Disk vault has system-assigned managed identity
###############################################################################
run "disk_vault_managed_identity" {
  command = plan

  assert {
    condition     = azurerm_data_protection_backup_vault.disk_vault.identity[0].type == "SystemAssigned"
    error_message = "disk vault must have SystemAssigned managed identity for RBAC (MINITRUE-9416)"
  }
}

###############################################################################
# Run 3 – OS disk snapshot policy: schedule, default retention, vault-tier rule
###############################################################################
run "os_disk_snapshot_policy" {
  command = plan

  assert {
    condition     = azurerm_data_protection_backup_policy_disk.os_disk.name == "dpbpol-os-disk-7d"
    error_message = "OS disk policy name must be dpbpol-os-disk-7d (MINITRUE-9416)"
  }

  assert {
    condition     = azurerm_data_protection_backup_policy_disk.os_disk.vault_id == azurerm_data_protection_backup_vault.disk_vault.id
    error_message = "OS disk policy must reference the correct disk vault"
  }

  # Hourly schedule via ISO 8601 repeating interval (every 4 hours)
  assert {
    condition     = contains(azurerm_data_protection_backup_policy_disk.os_disk.backup_repeating_time_intervals, "R/2024-01-01T02:00:00+00:00/PT4H")
    error_message = "OS disk policy must use PT4H (4-hour) repeating interval (MINITRUE-9416)"
  }

  # 7-day default (operational tier) retention
  assert {
    condition     = azurerm_data_protection_backup_policy_disk.os_disk.default_retention_duration == "P7D"
    error_message = "OS disk policy default retention must be P7D (7 days) (MINITRUE-9416)"
  }

  # Weekly vault-tier retention rule
  assert {
    condition     = azurerm_data_protection_backup_policy_disk.os_disk.retention_rule[0].name == "Weekly"
    error_message = "OS disk policy must have a Weekly vault-tier retention rule"
  }

  assert {
    condition     = azurerm_data_protection_backup_policy_disk.os_disk.retention_rule[0].duration == "P4W"
    error_message = "OS disk policy Weekly rule duration must be P4W (4 weeks)"
  }

  assert {
    condition     = azurerm_data_protection_backup_policy_disk.os_disk.retention_rule[0].priority == 25
    error_message = "OS disk policy Weekly rule priority must be 25"
  }

  assert {
    condition     = azurerm_data_protection_backup_policy_disk.os_disk.retention_rule[0].criteria[0].absolute_criteria == "FirstOfWeek"
    error_message = "OS disk policy Weekly rule must trigger on FirstOfWeek"
  }
}

###############################################################################
# Run 4 – Data disk snapshot policy: daily schedule and retention
###############################################################################
run "data_disk_snapshot_policy" {
  command = plan

  assert {
    condition     = azurerm_data_protection_backup_policy_disk.data_disk.name == "dpbpol-data-disk-7d"
    error_message = "data disk policy name must be dpbpol-data-disk-7d (MINITRUE-9416)"
  }

  # Daily schedule (P1D interval)
  assert {
    condition     = contains(azurerm_data_protection_backup_policy_disk.data_disk.backup_repeating_time_intervals, "R/2024-01-01T23:00:00+00:00/P1D")
    error_message = "data disk policy must use P1D (daily) repeating interval at 23:00 (MINITRUE-9416)"
  }

  assert {
    condition     = azurerm_data_protection_backup_policy_disk.data_disk.default_retention_duration == "P7D"
    error_message = "data disk policy default retention must be P7D (MINITRUE-9416)"
  }

  assert {
    condition     = azurerm_data_protection_backup_policy_disk.data_disk.retention_rule[0].duration == "P4W"
    error_message = "data disk Weekly vault-tier retention must be P4W"
  }
}

###############################################################################
# Run 5 – Backup vault output is populated
###############################################################################
run "disk_vault_output" {
  command = plan

  assert {
    condition     = output.data_protection_backup_vault_id != ""
    error_message = "data_protection_backup_vault_id output must not be empty (MINITRUE-9416)"
  }

  assert {
    condition     = can(regex("Microsoft.DataProtection/backupVaults", output.data_protection_backup_vault_id))
    error_message = "disk vault output ID must reference Microsoft.DataProtection/backupVaults"
  }
}

###############################################################################
# Run 6 – Cross-region snapshot copy Azure Policy is defined
###############################################################################
run "cross_region_snapshot_policy_defined" {
  command = plan

  assert {
    condition     = azurerm_policy_definition.cross_region_snapshot_copy.name == "pol-copy-snapshots-to-secondary"
    error_message = "cross-region snapshot copy policy must be defined (MINITRUE-9416 Task 3)"
  }

  assert {
    condition     = azurerm_policy_definition.cross_region_snapshot_copy.policy_type == "Custom"
    error_message = "cross-region snapshot copy policy must be Custom type"
  }

  assert {
    condition     = azurerm_policy_definition.cross_region_snapshot_copy.mode == "Indexed"
    error_message = "cross-region snapshot copy policy mode must be Indexed"
  }
}

###############################################################################
# Run 7 – Snapshot cleanup Azure Policy is defined
###############################################################################
run "snapshot_cleanup_policy_defined" {
  command = plan

  assert {
    condition     = azurerm_policy_definition.snapshot_cleanup.name == "pol-cleanup-old-snapshots"
    error_message = "snapshot cleanup policy must be defined (MINITRUE-9416 Task 4)"
  }

  assert {
    condition     = azurerm_policy_definition.snapshot_cleanup.mode == "All"
    error_message = "snapshot cleanup policy mode must be All"
  }
}

###############################################################################
# Run 8 – Role assignments exist for disk vault identity
###############################################################################
run "disk_vault_role_assignments" {
  command = plan

  assert {
    condition     = azurerm_role_assignment.disk_vault_snapshot_contributor.role_definition_name == "Disk Snapshot Contributor"
    error_message = "disk vault must have Disk Snapshot Contributor role (MINITRUE-9416)"
  }

  assert {
    condition     = azurerm_role_assignment.disk_vault_reader.role_definition_name == "Disk Backup Reader"
    error_message = "disk vault must have Disk Backup Reader role (MINITRUE-9416)"
  }

  assert {
    condition     = azurerm_role_assignment.disk_vault_snapshot_rg.role_definition_name == "Contributor"
    error_message = "disk vault must have Contributor role on snapshot resource group"
  }
}

###############################################################################
# Run 9 – Disk backup instances are zero when no disk IDs supplied
###############################################################################
run "no_disk_instances_when_empty" {
  command = plan

  assert {
    condition     = length(azurerm_data_protection_backup_instance_disk.app_os_disks) == 0
    error_message = "no app OS disk instances should be planned when app_vm_os_disk_ids is empty"
  }

  assert {
    condition     = length(azurerm_data_protection_backup_instance_disk.web_os_disks) == 0
    error_message = "no web OS disk instances should be planned when web_vm_os_disk_ids is empty"
  }

  assert {
    condition     = length(azurerm_data_protection_backup_instance_disk.app_data_disks) == 0
    error_message = "no app data disk instances should be planned when app_vm_data_disk_ids is empty"
  }

  assert {
    condition     = length(azurerm_data_protection_backup_instance_disk.web_data_disks) == 0
    error_message = "no web data disk instances should be planned when web_vm_data_disk_ids is empty"
  }
}
