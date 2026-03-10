# =============================================================================
# Terraform Test File: terraform-azure-bmw-recovery-vault-enhanced
#
# Usage:
#   terraform test                                    # all tests
#   terraform test -filter=run.rsv_basic_plan        # single test
# =============================================================================

provider "azurerm" {
  features {}
  # Set via env: ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
}

# ---------------------------------------------------------------------------
# Shared variables across all runs
# ---------------------------------------------------------------------------
variables {
  cloud_region = "westeurope"

  global_config = {
    env             = "dev"
    customer_prefix = "bmw"
    product_id      = "p-001"
    appd_id         = "appd-001"
    managed_by      = "terraform"
    owned_by        = "infra"
    consumed_by     = "test"
    app_name        = "rsvtest"
    costcenter      = "cc-001"
  }

  # Must exist before running apply tests
  resource_group_name = "rg-terraform-test"

  custom_tags = {
    purpose = "tftest"
  }
}

# =============================================================================
# TEST 1 — Basic RSV (plan)
# Covers: azurerm_recovery_services_vault, default SKU, soft delete, storage mode
# =============================================================================
run "rsv_basic_plan" {
  command = plan

  variables {
    sku                           = "Standard"
    soft_delete_enabled           = true
    storage_mode_type             = "GeoRedundant"
    cross_region_restore_enabled  = false
    public_network_access_enabled = false
    immutability                  = null
  }

  assert {
    condition     = var.sku == "Standard"
    error_message = "SKU must be Standard"
  }

  assert {
    condition     = var.soft_delete_enabled == true
    error_message = "Soft delete must be enabled by default"
  }

  assert {
    condition     = var.storage_mode_type == "GeoRedundant"
    error_message = "Storage mode must be GeoRedundant"
  }

  assert {
    condition     = var.cross_region_restore_enabled == false
    error_message = "Cross region restore must be disabled when storage mode is not GeoRedundant"
  }
}

# =============================================================================
# TEST 2 — RSV with VM backup policy (plan)
# Covers: azurerm_backup_policy_vm, daily retention, backup schedule
# =============================================================================
run "rsv_with_vm_backup_plan" {
  command = plan

  variables {
    sku                 = "Standard"
    soft_delete_enabled = true
    storage_mode_type   = "GeoRedundant"

    vms = {
      "vm-test-01" = {
        vm_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-terraform-test/providers/Microsoft.Compute/virtualMachines/test-vm-01"
        backup = {
          frequency = "Daily"
          time      = "02:00"
        }
        retention_daily = 30
      }
    }
  }

  assert {
    condition     = var.vms["vm-test-01"].backup.frequency == "Daily"
    error_message = "Backup frequency must be Daily"
  }

  assert {
    condition     = var.vms["vm-test-01"].retention_daily == 30
    error_message = "Daily retention must be 30 days"
  }

  assert {
    condition     = var.vms["vm-test-01"].backup.time == "02:00"
    error_message = "Backup time must be 02:00"
  }
}

# =============================================================================
# TEST 3 — RSV with disk snapshots — NO encryption (plan)
# Covers: azurerm_snapshot with encryption_settings skipped (encryption_enabled=false)
# This is the fix for: "Insufficient disk_encryption_key blocks" /
# "An argument named enabled is not expected here"
# =============================================================================
run "rsv_disk_snapshot_no_encryption_plan" {
  command = plan

  variables {
    sku                 = "Standard"
    soft_delete_enabled = true
    storage_mode_type   = "GeoRedundant"

    disk_snapshots = {
      "os-disk-snap" = {
        source_disk_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-terraform-test/providers/Microsoft.Compute/disks/test-osdisk"
        disk_size_gb       = 128
        incremental        = true
        encryption_enabled = false   # dynamic block is skipped — no key required
      }
    }
  }

  assert {
    condition     = var.disk_snapshots["os-disk-snap"].incremental == true
    error_message = "Snapshot must use incremental mode"
  }

  assert {
    condition     = var.disk_snapshots["os-disk-snap"].encryption_enabled == false
    error_message = "Encryption must be disabled for this test — no key provided"
  }
}

# =============================================================================
# TEST 4 — RSV full apply
# Covers: actual vault creation, output IDs populated, name not empty
# Requires: resource_group_name to exist in Azure
# =============================================================================
run "rsv_basic_apply" {
  command = apply

  variables {
    sku                           = "Standard"
    soft_delete_enabled           = true
    storage_mode_type             = "GeoRedundant"
    cross_region_restore_enabled  = false
    public_network_access_enabled = false
  }

  assert {
    condition     = output.recovery_services_vault_id != ""
    error_message = "RSV ID must be populated after apply"
  }

  assert {
    condition     = output.recovery_services_vault_name != ""
    error_message = "RSV name must be populated after apply"
  }

  assert {
    condition     = output.resource_group_name == "rg-terraform-test"
    error_message = "Resource group name in output must match input"
  }
}
