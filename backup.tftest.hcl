# Run with: terraform test

# ==========================================================
# TEST 1 - PLAN TEST (Safe)
# ==========================================================

run "plan_backup_vault" {
  command = plan

  module {
    source = "../"
  }

  variables {
    cloud_region        = "eastus"
    resource_group_name = "rg-backup-test"

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      app_name        = "backup-vault"
    }

    datastore_type = "VaultStore"
    soft_delete    = "AlwaysOn"
  }

  assert {
    condition     = var.soft_delete == "AlwaysOn"
    error_message = "Soft delete must be AlwaysOn"
  }
}

# ==========================================================
# TEST 2 - APPLY TEST (Creates Vault)
# ==========================================================

run "apply_backup_vault" {
  command = apply

  module {
    source = "../"
  }

  variables {
    cloud_region        = "eastus"
    resource_group_name = "rg-backup-test"

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      app_name        = "backup-vault"
    }

    datastore_type = "VaultStore"
    soft_delete    = "AlwaysOn"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.name != null
    error_message = "Backup vault should be created"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.soft_delete == "AlwaysOn"
    error_message = "Soft delete must be enabled"
  }
}
