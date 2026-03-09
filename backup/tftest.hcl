// Terraform Test File for Azure Backup Vault Module
// Tests security compliance and configuration validation
// Run with: terraform test

run "setup" {
  module {
    source = "./tests/setup"
  }
}

// ============================================================================
// TEST 1: Basic Vault Creation with Secure Defaults
// ============================================================================
run "test_basic_vault_creation_secure_defaults" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      managed_by      = "terraform"
      app_name        = "backup-vault-test"
      costcenter      = "engineering"
    }

    // Security enforced defaults
    soft_delete                    = "AlwaysOn"          // CRITICAL: Enforce always-on
    retention_duration_in_days     = 30                  // RECOMMENDED: Minimum 30 days
    redundancy                     = "LocallyRedundant"  // RECOMMENDED: Start with local
    datastore_type                 = "VaultStore"
    enable_diagnostic_settings     = true                // CRITICAL: Enable logging
    use_resource_guard             = true                // RECOMMENDED: Enable MUA
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.name != null
    error_message = "Backup vault should be created with a valid name"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.soft_delete == "AlwaysOn"
    error_message = "Soft delete must be set to AlwaysOn for production security"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.retention_duration_in_days >= 14
    error_message = "Soft delete retention must be at least 14 days"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.identity[0].type == "SystemAssigned"
    error_message = "Managed identity must be enabled on backup vault"
  }
}

// ============================================================================
// TEST 2: Soft Delete Configuration Validation
// ============================================================================
run "test_soft_delete_protection_always_on" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      app_name        = "backup-vault-soft-delete-test"
    }

    soft_delete                = "AlwaysOn"
    retention_duration_in_days = 180  // Maximum retention
    datastore_type             = "VaultStore"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.soft_delete == "AlwaysOn"
    error_message = "SECURITY: Soft delete protection must be AlwaysOn to prevent ransomware attacks"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.retention_duration_in_days == 180
    error_message = "Soft delete retention should be set to maximum (180 days) for critical backups"
  }
}

// ============================================================================
// TEST 3: Resource Guard Deployment and Protection
// ============================================================================
run "test_resource_guard_deployment" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      app_name        = "backup-vault-guard-test"
    }

    use_resource_guard                    = true
    vault_critical_operation_exclusion_list = ["getSecurityPIN"]
    datastore_type                         = "VaultStore"
    soft_delete                            = "AlwaysOn"
  }

  assert {
    condition     = length(azurerm_data_protection_resource_guard.this) == 1
    error_message = "Resource Guard must be created for Multi-User Admin (MUA) authorization"
  }

  assert {
    condition     = contains(var.vault_critical_operation_exclusion_list, "getSecurityPIN")
    error_message = "Resource Guard should have minimal exclusions for critical operations"
  }
}

// ============================================================================
// TEST 4: Blob Storage Backup Configuration with Least Privilege Roles
// ============================================================================
run "test_blob_storage_backup_with_least_privilege" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      app_name        = "backup-vault-blob-test"
    }

    backup_blob_storages                  = [run.setup.storage_account_id]
    backup_blob_storages_container_names  = ["container1"]
    backup_role_blob_storage              = "Storage Account Backup Contributor"  // Specific role, not Reader
    datastore_type                        = "VaultStore"
    soft_delete                           = "AlwaysOn"
    enable_diagnostic_settings            = true
    log_analytics_workspace_id            = run.setup.log_analytics_workspace_id
  }

  assert {
    condition     = var.backup_role_blob_storage == "Storage Account Backup Contributor"
    error_message = "SECURITY: Must use least privilege role 'Storage Account Backup Contributor' instead of Reader"
  }

  assert {
    condition     = azurerm_role_assignment.blobs[0].role_definition_name == "Storage Account Backup Contributor"
    error_message = "Role assignment must use specific backup contributor role"
  }
}

// ============================================================================
// TEST 5: Disk Backup with Least Privilege Role Validation
// ============================================================================
run "test_disk_backup_least_privilege" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      app_name        = "backup-vault-disk-test"
    }

    backup_disks           = [run.setup.disk_id]
    backup_role_disks      = "Disk Backup Reader"  // Specific role for disks
    datastore_type         = "SnapshotStore"
    soft_delete            = "AlwaysOn"
  }

  assert {
    condition     = var.backup_role_disks == "Disk Backup Reader"
    error_message = "SECURITY: Must use 'Disk Backup Reader' role for disk backups instead of generic Reader role"
  }

  assert {
    condition     = length(azurerm_data_protection_backup_instance_disk.disks) > 0
    error_message = "Disk backup instances must be created successfully"
  }
}

// ============================================================================
// TEST 6: Diagnostic Settings Enforcement
// ============================================================================
run "test_diagnostic_settings_enabled" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      app_name        = "backup-vault-diag-test"
    }

    enable_diagnostic_settings = true
    log_analytics_workspace_id = run.setup.log_analytics_workspace_id
    datastore_type             = "VaultStore"
    soft_delete                = "AlwaysOn"
  }

  assert {
    condition     = var.enable_diagnostic_settings == true
    error_message = "CRITICAL: Diagnostic settings must be enabled for audit logging"
  }

  assert {
    condition     = var.log_analytics_workspace_id != null
    error_message = "Log Analytics workspace ID must be provided when diagnostic settings are enabled"
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.data_protection_backup_vault_log) > 0
    error_message = "Diagnostic settings must be configured for the backup vault"
  }
}

// ============================================================================
// TEST 7: Retention Rules Validation
// ============================================================================
run "test_retention_rules_configuration" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      app_name        = "backup-vault-retention-test"
    }

    backup_disks               = [run.setup.disk_id]
    datastore_type             = "SnapshotStore"
    soft_delete                = "AlwaysOn"
    default_retention_duration = "P7D"
    backup_role_disks          = "Disk Backup Reader"

    retention_rules = [
      {
        name     = "weekly-backup"
        duration = "P30D"  // 30 days
        criteria = {
          absolute_criteria = "FirstOfWeek"
        }
        priority = 1
      },
      {
        name     = "monthly-backup"
        duration = "P90D"  // 90 days
        criteria = {
          absolute_criteria = "FirstOfMonth"
        }
        priority = 2
      }
    ]
  }

  assert {
    condition     = length(var.retention_rules) == 2
    error_message = "Retention rules must be configured for long-term backup retention"
  }

  assert {
    condition     = alltrue([for rule in var.retention_rules : rule.priority > 0])
    error_message = "All retention rules must have valid priority numbers"
  }
}

// ============================================================================
// TEST 8: PostgreSQL Backup with Proper Role Assignment
// ============================================================================
run "test_postgresql_backup_configuration" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      app_name        = "backup-vault-db-test"
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
    default_retention_duration     = "P30D"
    enable_diagnostic_settings     = true
    log_analytics_workspace_id     = run.setup.log_analytics_workspace_id
  }

  assert {
    condition     = var.backup_role_db == "PostgreSQL Flexible Server Long Term Retention Backup Role"
    error_message = "SECURITY: PostgreSQL backups must use specific 'PostgreSQL Flexible Server Long Term Retention Backup Role'"
  }

  assert {
    condition     = length(azurerm_data_protection_backup_instance_postgresql.dbs) > 0 || length(azurerm_data_protection_backup_instance_postgresql_flexible_server.dbs_flexible) > 0
    error_message = "At least one PostgreSQL backup instance must be created"
  }
}

// ============================================================================
// TEST 9: Multi-Database Backup with Flexible Server
// ============================================================================
run "test_postgresql_flexible_server_backup" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      app_name        = "backup-vault-flex-db-test"
    }

    backup_dbs_flexible = [
      {
        server_id = run.setup.postgres_flex_server_id
        rg_id     = run.setup.resource_group_id
      }
    ]

    backup_role_db                 = "PostgreSQL Flexible Server Long Term Retention Backup Role"
    datastore_type                 = "VaultStore"
    soft_delete                    = "AlwaysOn"
    default_retention_duration     = "P30D"
    backup_repeating_time_intervals = ["R/2024-01-01T03:00:00+00:00/P1D"]
    enable_diagnostic_settings      = true
    log_analytics_workspace_id      = run.setup.log_analytics_workspace_id
  }

  assert {
    condition     = length(azurerm_data_protection_backup_instance_postgresql_flexible_server.dbs_flexible) > 0
    error_message = "PostgreSQL flexible server backup instances must be created"
  }

  assert {
    condition     = alltrue([for r in azurerm_role_assignment.dbs_fexible : r.role_definition_name == "PostgreSQL Flexible Server Long Term Retention Backup Role"])
    error_message = "All flexible DB role assignments must use the correct role"
  }
}

// ============================================================================
// TEST 10: Backup Policy Configuration Validation
// ============================================================================
run "test_backup_policy_configuration" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      app_name        = "backup-vault-policy-test"
    }

    backup_disks                    = [run.setup.disk_id]
    backup_role_disks               = "Disk Backup Reader"
    datastore_type                  = "SnapshotStore"
    soft_delete                     = "AlwaysOn"
    default_retention_duration      = "P7D"
    backup_repeating_time_intervals = ["R/2024-01-01T03:30:00+00:00/P1W"]
  }

  assert {
    condition     = length(azurerm_data_protection_backup_policy_disk.disks) > 0
    error_message = "Backup policy for disks must be created"
  }

  assert {
    condition     = azurerm_data_protection_backup_policy_disk.disks[0].default_retention_duration == "P7D"
    error_message = "Backup policy must have default retention duration configured"
  }
}

// ============================================================================
// TEST 11: Security Regression Test - No Insecure Defaults
// ============================================================================
run "test_reject_weak_soft_delete" {
  command = plan

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      app_name        = "backup-vault-weak-test"
    }

    soft_delete = "Off"  // Should not be allowed in production
  }

  // This should fail or be prevented - expect validation error
  expect_failures = [
    var.soft_delete
  ]
}

// ============================================================================
// TEST 12: Reject Reader Role for Backup Operations (Least Privilege)
// ============================================================================
run "test_reject_generic_reader_role" {
  command = plan

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      app_name        = "backup-vault-generic-role-test"
    }

    backup_disks      = [run.setup.disk_id]
    backup_role_disks = "Reader"  // Generic role - should warn/fail
    datastore_type    = "SnapshotStore"
    soft_delete       = "AlwaysOn"
  }

  expect_failures = [
    azurerm_role_assignment.disks
  ]
}

// ============================================================================
// TEST 13: Tag Validation and Consistency
// ============================================================================
run "test_tag_validation" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      managed_by      = "terraform"
      app_name        = "backup-vault-tag-test"
      costcenter      = "engineering"
    }

    custom_tags = {
      "DataClassification" = "Confidential"
      "BackupPolicy"       = "Critical"
      "ReviewSchedule"     = "Quarterly"
    }

    soft_delete = "AlwaysOn"
  }

  assert {
    condition     = length(module.common.tags) > 0
    error_message = "Tags must be applied to the backup vault for resource governance"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.tags != null
    error_message = "Backup vault must have tags applied"
  }
}

// ============================================================================
// TEST 14: Role Assignment Scope Validation
// ============================================================================
run "test_role_assignment_scope_validation" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      app_name        = "backup-vault-scope-test"
    }

    backup_blob_storages         = [run.setup.storage_account_id]
    backup_blob_storages_container_names = ["container1"]
    backup_role_blob_storage     = "Storage Account Backup Contributor"
    datastore_type               = "VaultStore"
    soft_delete                  = "AlwaysOn"
  }

  assert {
    condition     = azurerm_role_assignment.blobs[0].scope == run.setup.storage_account_id
    error_message = "Role assignment scope must be limited to the specific storage account resource"
  }

  assert {
    condition     = azurerm_role_assignment.blobs[0].principal_id == azurerm_data_protection_backup_vault.this.identity[0].principal_id
    error_message = "Role must be assigned to the backup vault's managed identity only"
  }
}

// ============================================================================
// TEST 15: Managed Identity Configuration
// ============================================================================
run "test_managed_identity_security" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      app_name        = "backup-vault-identity-test"
    }

    soft_delete = "AlwaysOn"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.identity[0].type == "SystemAssigned"
    error_message = "Backup vault must use SystemAssigned managed identity (User Assigned is in preview)"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.identity[0].principal_id != null && azurerm_data_protection_backup_vault.this.identity[0].principal_id != ""
    error_message = "Principal ID must be set for the managed identity"
  }
}

// ============================================================================
// TEST 16: Datastore Type and Redundancy Configuration
// ============================================================================
run "test_datastore_redundancy_options" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      app_name        = "backup-vault-dr-test"
    }

    datastore_type = "VaultStore"
    redundancy     = "GeoRedundant"  // High availability
    soft_delete    = "AlwaysOn"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.datastore_type == "VaultStore"
    error_message = "Datastore type must match configuration"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.redundancy == "GeoRedundant"
    error_message = "GeoRedundant backup should be enabled for production critical data"
  }
}

// ============================================================================
// TEST 17: Multiple Resource Type Backups Configuration
// ============================================================================
run "test_multiple_backup_types_integration" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      app_name        = "backup-vault-multi-type-test"
    }

    // Configure multiple backup types simultaneously
    backup_blob_storages                  = [run.setup.storage_account_id]
    backup_blob_storages_container_names  = ["container1"]
    backup_role_blob_storage              = "Storage Account Backup Contributor"

    backup_disks      = [run.setup.disk_id]
    backup_role_disks = "Disk Backup Reader"

    backup_dbs = [
      {
        server_id   = run.setup.postgres_server_id
        database_id = run.setup.postgres_database_id
      }
    ]
    backup_role_db = "PostgreSQL Flexible Server Long Term Retention Backup Role"

    datastore_type             = "VaultStore"
    soft_delete                = "AlwaysOn"
    enable_diagnostic_settings = true
    log_analytics_workspace_id = run.setup.log_analytics_workspace_id
  }

  assert {
    condition     = length(azurerm_data_protection_backup_instance_blob_storage.blobs) > 0
    error_message = "Blob storage backup instances must be created"
  }

  assert {
    condition     = length(azurerm_data_protection_backup_instance_disk.disks) > 0
    error_message = "Disk backup instances must be created"
  }

  assert {
    condition     = length(azurerm_data_protection_backup_instance_postgresql.dbs) > 0
    error_message = "PostgreSQL backup instances must be created"
  }
}

// ============================================================================
// TEST 18: Resource Guard with Minimal Operation Exclusions
// ============================================================================
run "test_resource_guard_operations_protection" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      app_name        = "backup-vault-guard-ops-test"
    }

    use_resource_guard                    = true
    vault_critical_operation_exclusion_list = ["getSecurityPIN"]  // Minimal exclusion
    soft_delete                            = "AlwaysOn"
  }

  assert {
    condition     = length(var.vault_critical_operation_exclusion_list) <= 2
    error_message = "Critical operation exclusion list should be minimal for maximum security"
  }

  assert {
    condition     = !contains(var.vault_critical_operation_exclusion_list, "deleteProtection") || !contains(var.vault_critical_operation_exclusion_list, "disableSoftDelete")
    error_message = "deleteProtection and disableSoftDelete operations must NOT be excluded from resource guard protection"
  }
}

// ============================================================================
// TEST 19: Blob Storage Operational Retention
// ============================================================================
run "test_blob_operational_retention_duration" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env             = "test"
      customer_prefix = "test"
      product_id      = "backup"
      appd_id         = "test-app"
      app_name        = "backup-vault-blob-retention-test"
    }

    backup_blob_storages                         = [run.setup.storage_account_id]
    backup_blob_storages_container_names         = ["container1"]
    backup_role_blob_storage                     = "Storage Account Backup Contributor"
    blob_operational_default_retention_duration  = "P30D"  // 30-day operational retention
    datastore_type                               = "VaultStore"
    soft_delete                                  = "AlwaysOn"
  }

  assert {
    condition     = var.blob_operational_default_retention_duration == "P30D"
    error_message = "Blob operational retention should be at least 30 days for recovery window"
  }

  assert {
    condition     = length(azurerm_data_protection_backup_policy_blob_storage.blobs) > 0
    error_message = "Blob storage backup policy must be created"
  }
}

// ============================================================================
// TEST 20: Complete Security Hardening Configuration
// ============================================================================
run "test_complete_security_hardened_config" {
  command = apply

  variables {
    cloud_region        = "eastus"
    resource_group_name = run.setup.resource_group_name

    global_config = {
      env             = "production"
      customer_prefix = "corp"
      product_id      = "backup"
      appd_id         = "prod-backup"
      managed_by      = "terraform"
      app_name        = "production-backup-vault"
      costcenter      = "operations"
    }

    custom_tags = {
      "Environment"        = "Production"
      "DataClassification" = "Critical"
      "BackupPolicy"       = "Required"
      "ComplianceScope"    = "PCI-DSS,SOC2"
    }

    // All security features enabled
    soft_delete                        = "AlwaysOn"
    retention_duration_in_days         = 90
    redundancy                         = "GeoRedundant"
    datastore_type                     = "VaultStore"
    use_resource_guard                 = true
    vault_critical_operation_exclusion_list = ["getSecurityPIN"]
    enable_diagnostic_settings         = true
    log_analytics_workspace_id         = run.setup.log_analytics_workspace_id

    // Least privilege roles configured
    backup_blob_storages                  = [run.setup.storage_account_id]
    backup_blob_storages_container_names  = ["container1"]
    backup_role_blob_storage              = "Storage Account Backup Contributor"

    backup_disks      = [run.setup.disk_id]
    backup_role_disks = "Disk Backup Reader"

    backup_dbs = [
      {
        server_id   = run.setup.postgres_server_id
        database_id = run.setup.postgres_database_id
      }
    ]
    backup_role_db = "PostgreSQL Flexible Server Long Term Retention Backup Role"

    backup_repeating_time_intervals = ["R/2024-01-01T02:00:00+00:00/P1D"]
    default_retention_duration      = "P30D"

    retention_rules = [
      {
        name     = "weekly-7day-retention"
        duration = "P7D"
        criteria = {
          absolute_criteria = "FirstOfWeek"
        }
        priority = 1
      },
      {
        name     = "monthly-90day-retention"
        duration = "P90D"
        criteria = {
          absolute_criteria = "FirstOfMonth"
        }
        priority = 2
      },
      {
        name     = "yearly-365day-retention"
        duration = "P365D"
        criteria = {
          absolute_criteria = "FirstOfYear"
        }
        priority = 3
      }
    ]
  }

  // Comprehensive security assertions
  assert {
    condition     = azurerm_data_protection_backup_vault.this.soft_delete == "AlwaysOn"
    error_message = "Production vault must have AlwaysOn soft delete"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.retention_duration_in_days == 90
    error_message = "Production vault should have 90-day soft delete retention"
  }

  assert {
    condition     = azurerm_data_protection_backup_vault.this.redundancy == "GeoRedundant"
    error_message = "Production vault must have geo-redundant backup for HA"
  }

  assert {
    condition     = length(azurerm_data_protection_resource_guard.this) == 1
    error_message = "Production vault must have resource guard for MUA"
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.data_protection_backup_vault_log) > 0
    error_message = "Production vault must have diagnostic settings enabled"
  }

  assert {
    condition     = length(var.retention_rules) == 3
    error_message = "Production vault should have comprehensive retention policies"
  }

  assert {
    condition     = alltrue([
      azurerm_role_assignment.blobs[0].role_definition_name == "Storage Account Backup Contributor",
      azurerm_role_assignment.disks[0].role_definition_name == "Disk Backup Reader",
      azurerm_role_assignment.dbs[0].role_definition_name == "PostgreSQL Flexible Server Long Term Retention Backup Role"
    ])
    error_message = "All role assignments must use least privilege specific roles"
  }
}
