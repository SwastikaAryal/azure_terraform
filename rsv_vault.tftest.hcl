###############################################################################
# tests/rsv_vault.tftest.hcl
#
# Native Terraform test (terraform test) for MINITRUE-9348:
#   – Recovery Services Vault creation, configuration, and properties
#
# Run:  terraform test -filter=tests/rsv_vault.tftest.hcl
###############################################################################

# ── Shared variables used across all runs in this file ──────────────────────
variables {
  location                     = "eastus"
  secondary_location           = "westus"
  resource_group_name          = "rg-minitrue-test"
  environment                  = "test"
  vault_name                   = "rsv-minitrue-test"
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
# Run 1 – Vault exists and all required properties are set
###############################################################################
run "rsv_vault_is_created" {
  command = apply

  # Override: dev-specific vault name to avoid collisions
  variables {
    vault_name  = "rsv-minitrue-9348-test"
    environment = "test"
  }

  # ── Output sanity ──────────────────────────────────────────────────────
  assert {
    condition     = output.recovery_services_vault_id != ""
    error_message = "recovery_services_vault_id output must not be empty (MINITRUE-9348)"
  }

  assert {
    condition     = output.recovery_services_vault_name == "rsv-minitrue-9348-test"
    error_message = "vault name output does not match the configured vault_name variable"
  }

  assert {
    condition     = can(regex("Microsoft.RecoveryServices/vaults", output.recovery_services_vault_id))
    error_message = "vault resource ID must contain the correct Azure resource type"
  }

  # ── Resource-level property checks ────────────────────────────────────
  assert {
    condition     = azurerm_recovery_services_vault.main.sku == "Standard"
    error_message = "vault SKU must be Standard (MINITRUE-9348)"
  }

  assert {
    condition     = azurerm_recovery_services_vault.main.soft_delete_enabled == true
    error_message = "soft-delete must be enabled for 14-day recovery protection (MINITRUE-9348)"
  }

  assert {
    condition     = azurerm_recovery_services_vault.main.cross_region_restore_enabled == true
    error_message = "cross-region restore must be enabled (required by MINITRUE-9418)"
  }

  assert {
    condition     = azurerm_recovery_services_vault.main.storage_mode_type == "GeoRedundant"
    error_message = "storage mode must be GeoRedundant to support cross-region restore"
  }

  assert {
    condition     = azurerm_recovery_services_vault.main.immutability == "Unlocked"
    error_message = "immutability should be Unlocked (awaiting compliance sign-off)"
  }
}

###############################################################################
# Run 2 – Tags are applied correctly
###############################################################################
run "rsv_vault_tags_are_correct" {
  command = plan

  assert {
    condition = (
      azurerm_recovery_services_vault.main.tags["Environment"] == "test" &&
      azurerm_recovery_services_vault.main.tags["Project"]     == "MINITRUE" &&
      azurerm_recovery_services_vault.main.tags["ManagedBy"]   == "Terraform"
    )
    error_message = "vault must carry Environment, Project=MINITRUE, and ManagedBy=Terraform tags"
  }
}

###############################################################################
# Run 3 – Vault is associated with the correct resource group and location
###############################################################################
run "rsv_vault_location_and_rg" {
  command = plan

  assert {
    condition     = azurerm_recovery_services_vault.main.resource_group_name == var.resource_group_name
    error_message = "vault must be placed in the configured resource_group_name"
  }

  assert {
    condition     = azurerm_recovery_services_vault.main.location == var.location
    error_message = "vault location must match the configured primary location"
  }
}

###############################################################################
# Run 4 – Vault name variable is wired through correctly
###############################################################################
run "rsv_vault_name_variable_propagation" {
  command = plan

  variables {
    vault_name = "rsv-custom-name-check"
  }

  assert {
    condition     = azurerm_recovery_services_vault.main.name == "rsv-custom-name-check"
    error_message = "vault_name variable must propagate to the vault resource name"
  }
}
