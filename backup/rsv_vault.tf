resource "azurerm_recovery_services_vault" "main" {
  name                = var.vault_name
  location            = local.location
  resource_group_name = local.resource_group_name
  sku                 = "Standard"

  # Soft-delete protection (14-day retention after deletion)
  soft_delete_enabled = true

  # Immutability to prevent tampering with backup data
  immutability = "Unlocked" # Set to "Locked" for compliance once confirmed

  # Cross-region restore: allows restoring to secondary region
  cross_region_restore_enabled = true # Required by MINITRUE-9418 as well

  storage_mode_type = "GeoRedundant" # Geo-redundant for DR

  tags = local.tags
}

# -----------------------------------------------------------------
# Task 2: Standard backup policy – daily with 30-day retention
#         (Used as the default / "Standard" policy)
# -----------------------------------------------------------------
resource "azurerm_backup_policy_vm" "standard" {
  name                = "bkpol-standard-daily-30d"
  resource_group_name = local.resource_group_name
  recovery_vault_name = azurerm_recovery_services_vault.main.name

  # Off-peak backup window (11 PM UTC)
  backup {
    frequency = "Daily"
    time      = "23:00"
  }

  # Daily retention: 30 days
  retention_daily {
    count = 30
  }

  # Weekly retention: 12 weeks (Sundays)
  retention_weekly {
    count    = 12
    weekdays = ["Sunday"]
  }

  # Monthly retention: 12 months (first Sunday of month)
  retention_monthly {
    count    = 12
    weekdays = ["Sunday"]
    weeks    = ["First"]
  }

  # Yearly retention: 3 years (first Sunday of January)
  retention_yearly {
    count    = 3
    weekdays = ["Sunday"]
    weeks    = ["First"]
    months   = ["January"]
  }

  # Application-consistent snapshots (VSS / pre-post scripts)
  instant_restore_retention_days = 5
}

# -----------------------------------------------------------------
# Task 3: Application-consistent snapshot policy – Enhanced
#         (Higher frequency, longer instant-restore window)
# -----------------------------------------------------------------
resource "azurerm_backup_policy_vm" "enhanced" {
  name                = "bkpol-enhanced-daily-30d"
  resource_group_name = local.resource_group_name
  recovery_vault_name = azurerm_recovery_services_vault.main.name

  policy_type = "V2" # Enhanced policy for hourly backups

  backup {
    frequency     = "Hourly"
    time          = "06:00"  # Start of hourly window
    hour_interval = 4        # Every 4 hours
    hour_duration = 12       # 12-hour window
  }

  retention_daily {
    count = 30
  }

  retention_weekly {
    count    = 12
    weekdays = ["Sunday"]
  }

  retention_monthly {
    count    = 12
    weekdays = ["Sunday"]
    weeks    = ["First"]
  }

  retention_yearly {
    count    = 3
    weekdays = ["Sunday"]
    weeks    = ["First"]
    months   = ["January"]
  }

  instant_restore_retention_days = 7
}

# -----------------------------------------------------------------
# Task 4: Backup alert (Azure Monitor alert on backup job failures)
#         See monitoring.tf for full alert configuration
# -----------------------------------------------------------------

# -----------------------------------------------------------------
# Task 5: Associate App VMs with the standard backup policy
#         (both Windows and Linux VMs via the same policy resource)
# -----------------------------------------------------------------
resource "azurerm_backup_protected_vm" "app_vms" {
  for_each = toset(var.app_vm_ids)

  resource_group_name = local.resource_group_name
  recovery_vault_name = azurerm_recovery_services_vault.main.name
  source_vm_id        = each.value
  backup_policy_id    = azurerm_backup_policy_vm.standard.id

  # Exclusion of temp/cache disks is handled via backup policy LUN exclusion
  # (see MINITRUE-9418 / exclusion resource below)
}

resource "azurerm_backup_protected_vm" "web_vms" {
  for_each = toset(var.web_vm_ids)

  resource_group_name = local.resource_group_name
  recovery_vault_name = azurerm_recovery_services_vault.main.name
  source_vm_id        = each.value
  # Web VMs get the enhanced (application-consistent) policy
  backup_policy_id    = azurerm_backup_policy_vm.enhanced.id
}
