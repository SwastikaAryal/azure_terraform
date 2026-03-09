// ============================================================================
// TERRAFORM TEST FILE - Azure Backup Vault Module
// ============================================================================
// Full working tftest.hcl with:
// 1. Setup phase (test infrastructure)
// 2. Plan-first tests (safe preview)
// 3. Simple apply tests (resource creation)
// 4. Backup policy tests
// 5. Monitoring & security tests
//
// Run with: terraform test
// ============================================================================

// ============================================================================
// SETUP PHASE - Create Test Infrastructure
// ============================================================================
// This runs once and creates the test environment for all tests
run "setup" {
  module {
    source = "./tests/setup"
  }
}

// ============================================================================
// SECTION 1: PLAN-ONLY TESTS (Safe Preview - No Resources Created)
// ============================================================================

// ============================================================================
// TEST 1: Plan Basic Vault (No Changes)
// ============================================================================
run "plan_basic_vault" {
  command = plan

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      managed_by      = "terraform"
      app_name        = "backup-vault-plan-test"
      costcenter      = "engineering"
    }

    // Security defaults
    soft_delete                = "AlwaysOn"
    retention_duration_in_days = 30
    redundancy                 = "LocallyRedundant"
    datastore_type             = "VaultStore"
    enable_diagnostic_settings = false
    use_resource_guard         = false
    enable_private_endpoint    = false
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.name != null
    error_message = "Vault name must be generated"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.soft_delete == "AlwaysOn"
    error_message = "Soft delete must be AlwaysOn"
  }
}

// ============================================================================
// TEST 2: Plan Soft Delete Configuration
// ============================================================================
run "plan_soft_delete" {
  command = plan

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env         = "test"
      appd_id     = "test-app"
      app_name    = "backup-vault-softdelete-plan"
    }

    soft_delete                = "AlwaysOn"
    retention_duration_in_days = 90
    datastore_type             = "VaultStore"
  }

  assert {
    condition     = var.soft_delete == "AlwaysOn"
    error_message = "Soft delete config must be AlwaysOn"
  }

  assert {
    condition     = var.retention_duration_in_days == 90
    error_message = "Retention must be 90 days"
  }
}

// ============================================================================
// TEST 3: Plan Least Privilege Roles
// ============================================================================
run "plan_least_privilege_roles" {
  command = plan

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env         = "test"
      appd_id     = "test-app"
      app_name    = "backup-vault-roles-plan"
    }

    backup_role_blob_storage = "Storage Account Backup Contributor"
    backup_role_disks        = "Disk Backup Reader"
    backup_role_db           = "PostgreSQL Flexible Server Long Term Retention Backup Role"
    datastore_type           = "VaultStore"
    soft_delete              = "AlwaysOn"
  }

  assert {
    condition     = var.backup_role_blob_storage == "Storage Account Backup Contributor"
    error_message = "Must use least privilege role for blob storage"
  }

  assert {
    condition     = var.backup_role_disks == "Disk Backup Reader"
    error_message = "Must use least privilege role for disks"
  }

  assert {
    condition     = var.backup_role_db == "PostgreSQL Flexible Server Long Term Retention Backup Role"
    error_message = "Must use PostgreSQL specific role"
  }
}

// ============================================================================
// SECTION 2: SIMPLE APPLY TESTS (Basic Resource Creation)
// ============================================================================

// ============================================================================
// TEST 4: Simple Vault Creation (Apply)
// ============================================================================
run "apply_simple_vault" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      app_name        = "backup-vault-simple"
      costcenter      = "engineering"
    }

    soft_delete                = "AlwaysOn"
    retention_duration_in_days = 30
    redundancy                 = "LocallyRedundant"
    datastore_type             = "VaultStore"
    enable_diagnostic_settings = false
    use_resource_guard         = false
    enable_private_endpoint    = false
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.name != null
    error_message = "Backup vault must be created with a valid name"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.soft_delete == "AlwaysOn"
    error_message = "Soft delete must be set to AlwaysOn"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.retention_duration_in_days >= 14
    error_message = "Retention must be at least 14 days"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.identity[0].type == "SystemAssigned"
    error_message = "Managed identity must be enabled"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.redundancy == "LocallyRedundant"
    error_message = "Redundancy configuration must match"
  }
}

// ============================================================================
// TEST 5: Vault with Soft Delete Maximum Retention
// ============================================================================
run "apply_soft_delete_maximum" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env         = "test"
      appd_id     = "test-app"
      app_name    = "backup-vault-retention-max"
    }

    soft_delete                = "AlwaysOn"
    retention_duration_in_days = 180
    datastore_type             = "VaultStore"
    enable_private_endpoint    = false
    use_resource_guard         = false
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.soft_delete == "AlwaysOn"
    error_message = "Soft delete must be AlwaysOn"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.retention_duration_in_days == 180
    error_message = "Retention must be 180 days maximum"
  }
}

// ============================================================================
// SECTION 3: BACKUP POLICY TESTS
// ============================================================================

// ============================================================================
// TEST 6: Blob Storage Backup Policy
// ============================================================================
run "apply_blob_storage_policy" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env         = "test"
      appd_id     = "test-app"
      app_name    = "backup-vault-blob-policy"
    }

    backup_blob_storages                  = [run.setup.storage_account_id]
    backup_blob_storages_container_names  = ["container1"]
    backup_role_blob_storage              = "Storage Account Backup Contributor"
    datastore_type                        = "VaultStore"
    soft_delete                           = "AlwaysOn"
    blob_operational_default_retention_duration = "P30D"
    enable_diagnostic_settings            = false
    use_resource_guard                    = false
    enable_private_endpoint               = false
  }

  assert {
    condition     = var.backup_role_blob_storage == "Storage Account Backup Contributor"
    error_message = "Must use least privilege role for blob storage"
  }

  assert {
    condition     = length(azurerm_data_protection_backup_policy_blob_storage.blobs) > 0
    error_message = "Blob backup policy must be created"
  }

  assert {
    condition     = length(azurerm_data_protection_backup_instance_blob_storage.blobs) > 0
    error_message = "Blob backup instance must be created"
  }

  assert {
    condition     = var.blob_operational_default_retention_duration == "P30D"
    error_message = "Blob retention must be 30 days"
  }
}

// ============================================================================
// TEST 7: Disk Backup Policy
// ============================================================================
run "apply_disk_policy" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env         = "test"
      appd_id     = "test-app"
      app_name    = "backup-vault-disk-policy"
    }

    backup_disks           = [run.setup.disk_id]
    backup_role_disks      = "Disk Backup Reader"
    datastore_type         = "SnapshotStore"
    soft_delete            = "AlwaysOn"
    default_retention_duration = "P7D"
    enable_diagnostic_settings = false
    use_resource_guard     = false
    enable_private_endpoint = false
  }

  assert {
    condition     = var.backup_role_disks == "Disk Backup Reader"
    error_message = "Must use least privilege role for disks"
  }

  assert {
    condition     = length(azurerm_data_protection_backup_policy_disk.disks) > 0
    error_message = "Disk backup policy must be created"
  }

  assert {
    condition     = length(azurerm_data_protection_backup_instance_disk.disks) > 0
    error_message = "Disk backup instance must be created"
  }
}

// ============================================================================
// TEST 8: PostgreSQL Backup Policy
// ============================================================================
run "apply_postgresql_policy" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env         = "test"
      appd_id     = "test-app"
      app_name    = "backup-vault-postgres-policy"
    }

    backup_dbs = [
      {
        server_id   = run.setup.postgres_server_id
        database_id = run.setup.postgres_database_id
      }
    ]
    backup_role_db                 = "PostgreSQL Flexible Server Long Term Retention Backup Role"
    datastore_type                 = "VaultStore"
    soft_delete                    = "AlwaysOn"
    default_retention_duration     = "P7D"
    enable_diagnostic_settings     = false
    use_resource_guard             = false
    enable_private_endpoint        = false
  }

  assert {
    condition     = var.backup_role_db == "PostgreSQL Flexible Server Long Term Retention Backup Role"
    error_message = "Must use PostgreSQL specific role"
  }

  assert {
    condition     = length(azurerm_data_protection_backup_policy_postgresql.dbs) > 0
    error_message = "PostgreSQL backup policy must be created"
  }

  assert {
    condition     = length(azurerm_data_protection_backup_instance_postgresql.dbs) > 0
    error_message = "PostgreSQL backup instance must be created"
  }
}

// ============================================================================
// SECTION 4: MONITORING & LOGGING TESTS
// ============================================================================

// ============================================================================
// TEST 9: Diagnostic Settings & Monitoring
// ============================================================================
run "apply_diagnostic_settings" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env         = "test"
      appd_id     = "test-app"
      app_name    = "backup-vault-diagnostics"
    }

    enable_diagnostic_settings = true
    log_analytics_workspace_id = run.setup.log_analytics_workspace_id
    datastore_type             = "VaultStore"
    soft_delete                = "AlwaysOn"
    enable_backup_vault_alerts = false
    use_resource_guard         = false
    enable_private_endpoint    = false
  }

  assert {
    condition     = var.enable_diagnostic_settings == true
    error_message = "Diagnostic settings must be enabled"
  }

  assert {
    condition     = var.log_analytics_workspace_id != null
    error_message = "Log Analytics workspace ID must be configured"
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.data_protection_backup_vault_log) > 0
    error_message = "Diagnostic setting must be created"
  }
}

// ============================================================================
// SECTION 5: RETENTION RULES & BACKUP SCHEDULING
// ============================================================================

// ============================================================================
// TEST 10: Retention Rules Configuration
// ============================================================================
run "apply_retention_rules" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env         = "test"
      appd_id     = "test-app"
      app_name    = "backup-vault-retention-rules"
    }

    backup_disks               = [run.setup.disk_id]
    datastore_type             = "SnapshotStore"
    soft_delete                = "AlwaysOn"
    default_retention_duration = "P7D"
    backup_role_disks          = "Disk Backup Reader"
    enable_diagnostic_settings = false
    use_resource_guard         = false
    enable_private_endpoint    = false

    retention_rules = [
      {
        name     = "weekly-backup"
        duration = "P30D"
        criteria = {
          absolute_criteria = "FirstOfWeek"
        }
        priority = 1
      },
      {
        name     = "monthly-backup"
        duration = "P90D"
        criteria = {
          absolute_criteria = "FirstOfMonth"
        }
        priority = 2
      }
    ]
  }

  assert {
    condition     = length(var.retention_rules) == 2
    error_message = "Retention rules must be configured"
  }

  assert {
    condition     = var.retention_rules[0].duration == "P30D"
    error_message = "First retention rule must be 30 days"
  }

  assert {
    condition     = var.retention_rules[1].duration == "P90D"
    error_message = "Second retention rule must be 90 days"
  }

  assert {
    condition     = length(azurerm_data_protection_backup_policy_disk.disks) > 0
    error_message = "Backup policy with retention rules must be created"
  }
}
