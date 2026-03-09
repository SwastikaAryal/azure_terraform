# Backup Vault Security Remediation Guide

## Overview
This guide provides step-by-step instructions to implement all security fixes for the Azure Backup Vault Terraform module.

---

## FIX #1: Enable Customer-Managed Key (CMK) Encryption

### 📋 File: `variables.tf`

Add these variables at the end of the file:

```hcl
# =====================================================================
# Customer-Managed Key (CMK) Configuration
# =====================================================================
variable "enable_customer_managed_key" {
  type        = bool
  description = "Enable customer-managed keys (CMK) for backup vault encryption. Recommended for production environments handling sensitive data."
  default     = false

  validation {
    condition     = can(coalesce(var.enable_customer_managed_key))
    error_message = "enable_customer_managed_key must be a valid boolean value"
  }
}

variable "key_vault_id" {
  type        = string
  description = "Azure Key Vault ID containing the encryption key. Required when enable_customer_managed_key is true."
  default     = null

  validation {
    condition     = var.enable_customer_managed_key ? (var.key_vault_id != null && can(regex("^/subscriptions/.*/providers/Microsoft.KeyVault/vaults/", var.key_vault_id))) : true
    error_message = "When CMK is enabled, key_vault_id must be a valid Key Vault resource ID"
  }
}

variable "key_vault_key_name" {
  type        = string
  description = "Name of the key in Key Vault to use for encryption"
  default     = null
}

variable "key_vault_key_version" {
  type        = string
  description = "Version of the Key Vault key to use (optional, uses latest if not specified)"
  default     = null
}

variable "user_assigned_identity_id" {
  type        = string
  description = "User-assigned managed identity ID for CMK access. If not provided, one will be created."
  default     = null
}
```

### 📝 File: `main.tf`

Add a data source at the beginning to get current subscription context:

```hcl
data "azurerm_client_config" "current" {}
```

Replace the backup vault resource with enhanced encryption configuration:

```hcl
# =====================================================================
# User-Assigned Identity for CMK Access (if not provided)
# =====================================================================
resource "azurerm_user_assigned_identity" "vault_cmk" {
  count               = var.enable_customer_managed_key && var.user_assigned_identity_id == null ? 1 : 0
  name                = "${module.common.names.resource_type["azurerm_data_protection_backup_vault"].name}-cmk-uai"
  resource_group_name = var.resource_group_name
  location            = var.cloud_region

  tags = merge(
    module.common.tags,
    { "Purpose" = "BackupVaultCMKAccess" }
  )
}

# =====================================================================
# Key Vault Access Policy for CMK
# =====================================================================
resource "azurerm_key_vault_access_policy" "vault_cmk" {
  count       = var.enable_customer_managed_key ? 1 : 0
  key_vault_id = var.key_vault_id

  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = coalesce(
    var.user_assigned_identity_id != null ? data.azurerm_user_assigned_identity.existing_cmk[0].principal_id : null,
    azurerm_user_assigned_identity.vault_cmk[0].principal_id
  )

  key_permissions = [
    "Get",
    "Decrypt",
    "Encrypt",
    "WrapKey",
    "UnwrapKey",
    "Sign",
    "Verify"
  ]

  secret_permissions = []
  certificate_permissions = []
}

# =====================================================================
# Reference existing user-assigned identity if provided
# =====================================================================
data "azurerm_user_assigned_identity" "existing_cmk" {
  count = var.enable_customer_managed_key && var.user_assigned_identity_id != null ? 1 : 0

  resource_id = var.user_assigned_identity_id
}

# =====================================================================
# Backup Vault with CMK Support
# =====================================================================
resource "azurerm_data_protection_backup_vault" "this" {
  name                = module.common.names.resource_type["azurerm_data_protection_backup_vault"].name
  resource_group_name = var.resource_group_name
  location            = var.cloud_region

  datastore_type = var.datastore_type
  redundancy     = var.redundancy

  # ===================== CRITICAL SECURITY FIX =====================
  # Managed Identity Configuration - ALWAYS ENABLED
  identity {
    type = "SystemAssigned"
    # Add user-assigned identity for CMK if enabled
    identity_ids = var.enable_customer_managed_key ? [
      coalesce(
        var.user_assigned_identity_id,
        azurerm_user_assigned_identity.vault_cmk[0].id
      )
    ] : []
  }

  # ===================== CRITICAL SECURITY FIX =====================
  # Customer-Managed Key (CMK) Encryption Configuration
  dynamic "encryption" {
    for_each = var.enable_customer_managed_key ? [1] : []
    content {
      key_vault_key_id = var.key_vault_id != null ? "${var.key_vault_id}/keys/${var.key_vault_key_name}${var.key_vault_key_version != null ? "/versions/${var.key_vault_key_version}" : ""}" : null
      user_assigned_identity_id = coalesce(
        var.user_assigned_identity_id,
        azurerm_user_assigned_identity.vault_cmk[0].id
      )
      infrastructure_encryption_enabled = true
    }
  }

  retention_duration_in_days = var.retention_duration_in_days
  soft_delete                = var.soft_delete

  tags = module.common.tags

  depends_on = [azurerm_key_vault_access_policy.vault_cmk]
}
```

### 📌 Usage Example:

```hcl
module "backup_vault" {
  source = "./"

  cloud_region        = "eastus"
  resource_group_name = "my-rg"
  
  global_config = {
    env         = "production"
    appd_id     = "backup-app"
    app_name    = "backup"
  }

  # SECURITY: Enable customer-managed key encryption
  enable_customer_managed_key = true
  key_vault_id                = azurerm_key_vault.this.id
  key_vault_key_name          = "backup-vault-key"
  
  soft_delete                = "AlwaysOn"
  retention_duration_in_days = 90
}
```

---

## FIX #2: Implement Private Endpoints and Network Controls

### 📋 File: `variables.tf`

Add network security variables:

```hcl
# =====================================================================
# Network Security Configuration
# =====================================================================
variable "enable_private_endpoint" {
  type        = bool
  description = "Enable private endpoint for secure backup vault access (recommended for production)"
  default     = true
}

variable "virtual_network_id" {
  type        = string
  description = "Azure Virtual Network ID for private endpoint (required when enable_private_endpoint is true)"
  default     = null

  validation {
    condition     = (var.enable_private_endpoint && var.virtual_network_id != null) || !var.enable_private_endpoint
    error_message = "virtual_network_id is required when enable_private_endpoint is true"
  }
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID where private endpoint will be deployed (required when enable_private_endpoint is true)"
  default     = null

  validation {
    condition     = (var.enable_private_endpoint && var.subnet_id != null) || !var.enable_private_endpoint
    error_message = "subnet_id is required when enable_private_endpoint is true"
  }
}

variable "private_endpoint_name" {
  type        = string
  description = "Name for the private endpoint (auto-generated if not provided)"
  default     = null
}

variable "private_dns_zone_resource_group_name" {
  type        = string
  description = "Resource group containing the private DNS zone (auto-created in target RG if not specified)"
  default     = null
}

variable "enable_private_dns_zone_link" {
  type        = bool
  description = "Create/link private DNS zone for backup vault"
  default     = true
}

variable "allowed_ip_ranges" {
  type        = list(string)
  description = "List of allowed IP ranges for backup vault access (if public endpoint is used)"
  default     = []
}
```

### 📝 File: `main.tf`

Add after the backup vault resource definition:

```hcl
# =====================================================================
# CRITICAL SECURITY FIX: Private Endpoint for Backup Vault
# =====================================================================
resource "azurerm_private_endpoint" "backup_vault" {
  count               = var.enable_private_endpoint ? 1 : 0
  name                = coalesce(var.private_endpoint_name, "${module.common.names.resource_type["azurerm_data_protection_backup_vault"].name}-pep")
  location            = var.cloud_region
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "${module.common.names.resource_type["azurerm_data_protection_backup_vault"].name}-psc"
    private_connection_resource_id = azurerm_data_protection_backup_vault.this.id
    subresource_names              = ["AzureBackup"]
    is_manual_connection           = false
  }

  tags = merge(
    module.common.tags,
    { "Purpose" = "BackupVaultPrivateAccess" }
  )
}

# =====================================================================
# Private DNS Zone for Backup Vault
# =====================================================================
resource "azurerm_private_dns_zone" "backup_vault" {
  count               = var.enable_private_endpoint && var.enable_private_dns_zone_link ? 1 : 0
  name                = "privatelink.backup.azure.com"
  resource_group_name = coalesce(var.private_dns_zone_resource_group_name, var.resource_group_name)

  tags = merge(
    module.common.tags,
    { "Purpose" = "BackupVaultDNS" }
  )
}

# =====================================================================
# Virtual Network Link for Private DNS Zone
# =====================================================================
resource "azurerm_private_dns_zone_virtual_network_link" "backup_vault" {
  count                 = var.enable_private_endpoint && var.enable_private_dns_zone_link ? 1 : 0
  name                  = "${azurerm_private_dns_zone.backup_vault[0].name}-link"
  resource_group_name   = coalesce(var.private_dns_zone_resource_group_name, var.resource_group_name)
  private_dns_zone_name = azurerm_private_dns_zone.backup_vault[0].name
  virtual_network_id    = var.virtual_network_id

  tags = module.common.tags
}

# =====================================================================
# Private DNS A Record for Backup Vault
# =====================================================================
resource "azurerm_private_dns_a_record" "backup_vault" {
  count               = var.enable_private_endpoint && var.enable_private_dns_zone_link ? 1 : 0
  name                = azurerm_data_protection_backup_vault.this.name
  zone_name           = azurerm_private_dns_zone.backup_vault[0].name
  resource_group_name = coalesce(var.private_dns_zone_resource_group_name, var.resource_group_name)
  ttl                 = 300
  records             = [azurerm_private_endpoint.backup_vault[0].private_service_connection[0].private_ip_address]

  tags = module.common.tags
}

# =====================================================================
# Management Lock to Prevent Deletion
# =====================================================================
resource "azurerm_management_lock" "backup_vault_delete_lock" {
  name       = "backup-vault-cannot-delete"
  scope      = azurerm_data_protection_backup_vault.this.id
  lock_level = "CanNotDelete"
  notes      = "Prevent accidental or malicious deletion of critical backup vault"
}
```

### 📌 Usage Example:

```hcl
module "backup_vault" {
  source = "./"

  cloud_region        = "eastus"
  resource_group_name = "my-rg"
  
  global_config = {
    env     = "production"
    appd_id = "backup-app"
    app_name = "backup"
  }

  # SECURITY: Enable private endpoint
  enable_private_endpoint                    = true
  virtual_network_id                        = azurerm_virtual_network.this.id
  subnet_id                                 = azurerm_subnet.private.id
  enable_private_dns_zone_link              = true
  private_dns_zone_resource_group_name      = azurerm_resource_group.this.name
  
  soft_delete                = "AlwaysOn"
  retention_duration_in_days = 90
}
```

---

## FIX #3: Enforce AlwaysOn Soft Delete

### 📋 File: `variables.tf`

Update the soft_delete variable:

```hcl
variable "soft_delete" {
  type        = string
  description = "The state of soft delete for this Backup Vault. Possible values are 'AlwaysOn', 'On', 'Off'. Default 'AlwaysOn' for maximum protection."
  default     = "AlwaysOn"

  validation {
    condition     = contains(["AlwaysOn", "On", "Off"], var.soft_delete)
    error_message = "soft_delete must be one of: AlwaysOn, On, Off"
  }
}

variable "enforce_soft_delete_always_on" {
  type        = bool
  description = "Override soft_delete variable and enforce AlwaysOn in production environments"
  default     = false
}

variable "retention_duration_in_days" {
  type        = number
  description = "The soft delete retention duration for this Backup Vault. Possible values are between 14 and 180 days."
  default     = 30

  validation {
    condition     = var.retention_duration_in_days >= 14 && var.retention_duration_in_days <= 180
    error_message = "retention_duration_in_days must be between 14 (minimum) and 180 (maximum) days"
  }
}
```

### 📝 File: `main.tf`

Update the backup vault resource:

```hcl
resource "azurerm_data_protection_backup_vault" "this" {
  name                = module.common.names.resource_type["azurerm_data_protection_backup_vault"].name
  resource_group_name = var.resource_group_name
  location            = var.cloud_region

  datastore_type = var.datastore_type
  redundancy     = var.redundancy

  identity {
    type = "SystemAssigned"
  }

  retention_duration_in_days = var.retention_duration_in_days
  
  # ===================== CRITICAL SECURITY FIX =====================
  # Enforce AlwaysOn soft delete in production
  soft_delete = var.enforce_soft_delete_always_on ? "AlwaysOn" : var.soft_delete

  tags = module.common.tags

  # ===================== VALIDATION =====================
  lifecycle {
    precondition {
      condition     = var.retention_duration_in_days >= 30
      error_message = "RECOMMENDED: Soft delete retention should be at least 30 days for adequate recovery window"
    }
  }
}
```

---

## FIX #4: Implement Least Privilege Role Assignments

### 📋 File: `variables.tf`

Update role variables with validations:

```hcl
variable "backup_role_blob_storage" {
  type        = string
  description = "Role for Blob Storage backups. Recommended: 'Storage Account Backup Contributor' (least privilege). Set to empty string to skip assignment."
  default     = "Storage Account Backup Contributor"

  validation {
    condition     = contains(["", "Storage Account Backup Contributor", "Reader"], var.backup_role_blob_storage)
    error_message = "Use 'Storage Account Backup Contributor' for least privilege, not 'Reader'"
  }
}

variable "backup_role_disks" {
  type        = string
  description = "Role for Disk backups. Recommended: 'Disk Backup Reader' (least privilege). Set to empty string to skip assignment."
  default     = "Disk Backup Reader"

  validation {
    condition     = contains(["", "Disk Backup Reader", "Disk Snapshot Contributor", "Reader"], var.backup_role_disks)
    error_message = "Use 'Disk Backup Reader' or 'Disk Snapshot Contributor' for least privilege, not 'Reader'"
  }
}

variable "backup_role_db" {
  type        = string
  description = "Role for PostgreSQL backups. Recommended: 'PostgreSQL Flexible Server Long Term Retention Backup Role' (least privilege). Set to empty string to skip assignment."
  default     = "PostgreSQL Flexible Server Long Term Retention Backup Role"

  validation {
    condition     = contains(["", "PostgreSQL Flexible Server Long Term Retention Backup Role", "Reader"], var.backup_role_db)
    error_message = "Use 'PostgreSQL Flexible Server Long Term Retention Backup Role' for least privilege, not 'Reader'"
  }
}

variable "enable_role_assignment_validation" {
  type        = bool
  description = "Enable strict validation of role assignments to prevent overly broad permissions"
  default     = true
}
```

### 📝 File: `main.tf`

Add validation and update role assignments:

```hcl
# =====================================================================
# SECURITY: Role Assignment Validation
# =====================================================================
locals {
  reader_role_warning = {
    blobs  = var.backup_role_blob_storage == "Reader" ? "WARNING: Using generic 'Reader' role for Blob Storage is not recommended" : null
    disks  = var.backup_role_disks == "Reader" ? "WARNING: Using generic 'Reader' role for Disks is not recommended" : null
    dbs    = var.backup_role_db == "Reader" ? "WARNING: Using generic 'Reader' role for PostgreSQL is not recommended" : null
  }
}

# =====================================================================
# Blob Storage Role Assignment (Updated)
# =====================================================================
resource "azurerm_role_assignment" "blobs" {
  count = var.backup_role_blob_storage != "" ? length(var.backup_blob_storages) : 0

  scope              = var.backup_blob_storages[count.index]
  role_definition_name = var.backup_role_blob_storage
  principal_id       = azurerm_data_protection_backup_vault.this.identity[0].principal_id

  lifecycle {
    precondition {
      condition     = var.backup_role_blob_storage != "Reader"
      error_message = "SECURITY: Use 'Storage Account Backup Contributor' instead of generic 'Reader' role for least privilege"
    }
  }
}

# =====================================================================
# Disk Role Assignment (Updated)
# =====================================================================
resource "azurerm_role_assignment" "disks" {
  count = var.backup_role_disks != "" ? length(var.backup_disks) : 0

  scope              = var.backup_disks[count.index]
  role_definition_name = var.backup_role_disks
  principal_id       = azurerm_data_protection_backup_vault.this.identity[0].principal_id

  lifecycle {
    precondition {
      condition     = !contains(["Reader"], var.backup_role_disks)
      error_message = "SECURITY: Use 'Disk Backup Reader' or 'Disk Snapshot Contributor' instead of generic 'Reader' role"
    }
  }
}

# =====================================================================
# PostgreSQL Role Assignment (Updated)
# =====================================================================
resource "azurerm_role_assignment" "dbs" {
  count = var.backup_role_db != "" ? length(var.backup_dbs) : 0

  scope              = var.backup_dbs[count.index].server_id
  role_definition_name = var.backup_role_db
  principal_id       = azurerm_data_protection_backup_vault.this.identity[0].principal_id

  lifecycle {
    precondition {
      condition     = !contains(["Reader"], var.backup_role_db)
      error_message = "SECURITY: Use service-specific roles instead of generic 'Reader' role for least privilege"
    }
  }
}
```

---

## FIX #5: Enforce Diagnostic Settings

### 📋 File: `variables.tf`

Update diagnostic settings variables:

```hcl
variable "enable_diagnostic_settings" {
  type        = bool
  description = "Enable diagnostic settings for audit logging (CRITICAL for production). Default true."
  default     = true
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Log Analytics Workspace ID for sending diagnostic logs (required when diagnostic settings enabled)"
  default     = null

  validation {
    condition     = can(regex("^/subscriptions/.*/providers/Microsoft.OperationalInsights/workspaces/", var.log_analytics_workspace_id)) || var.log_analytics_workspace_id == null
    error_message = "log_analytics_workspace_id must be a valid Log Analytics workspace resource ID"
  }
}

variable "enable_backup_vault_alerts" {
  type        = bool
  description = "Enable metric alerts for backup vault"
  default     = true
}

variable "alert_action_group_id" {
  type        = string
  description = "Action Group ID for sending backup vault alerts"
  default     = null
}
```

### 📝 File: `main.tf`

Update diagnostic settings and add alerts:

```hcl
# =====================================================================
# Diagnostic Settings (Updated - ALWAYS ENABLED FOR PRODUCTION)
# =====================================================================
data "azurerm_monitor_diagnostic_categories" "data_protection_backup_vault_log" {
  count       = var.enable_diagnostic_settings ? 1 : 0
  resource_id = azurerm_data_protection_backup_vault.this.id
}

resource "azurerm_monitor_diagnostic_setting" "data_protection_backup_vault_log" {
  count = var.enable_diagnostic_settings ? 1 : 0

  name                           = "${module.common.names.resource_type["azurerm_data_protection_backup_vault"].name}-diagnostic-setting"
  target_resource_id             = azurerm_data_protection_backup_vault.this.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = "AzureDiagnostics"

  dynamic "enabled_log" {
    iterator = log_category
    for_each = data.azurerm_monitor_diagnostic_categories.data_protection_backup_vault_log[0].log_category_types

    content {
      category = log_category.value
      enabled  = true
    }
  }

  dynamic "enabled_metric" {
    for_each = data.azurerm_monitor_diagnostic_categories.data_protection_backup_vault_log[0].metrics
    content {
      category = enabled_metric.value
      enabled  = true
    }
  }

  lifecycle {
    precondition {
      condition     = var.log_analytics_workspace_id != null
      error_message = "CRITICAL: log_analytics_workspace_id must be provided when diagnostic settings are enabled"
    }
  }
}

# =====================================================================
# Backup Vault Alerts (Optional but Recommended)
# =====================================================================
resource "azurerm_monitor_metric_alert" "backup_vault_failed_operations" {
  count = var.enable_backup_vault_alerts && var.alert_action_group_id != null ? 1 : 0

  name                = "${module.common.names.resource_type["azurerm_data_protection_backup_vault"].name}-failed-operations-alert"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_data_protection_backup_vault.this.id]
  description         = "Alert when backup operations fail"
  severity            = 2

  criteria {
    metric_name        = "OperationsFailed"
    metric_namespace   = "Microsoft.DataProtection/backupVaults"
    operator           = "GreaterThan"
    threshold          = 0
    statistic          = "Total"
    aggregation        = "Total"
    skip_metric_validation = false
  }

  action {
    action_group_id = var.alert_action_group_id
  }

  tags = module.common.tags
}
```

---

## Summary Checklist

After implementing all fixes:

- [ ] CMK encryption enabled with Key Vault integration
- [ ] Private endpoints configured for network isolation
- [ ] Management locks prevent vault deletion
- [ ] Soft delete set to AlwaysOn with 30+ day retention
- [ ] Least privilege roles assigned (no Reader role)
- [ ] Diagnostic settings enabled with Log Analytics
- [ ] Resource Guard deployed for MUA scenarios
- [ ] All variables validated with preconditions
- [ ] Tags properly applied to all resources
- [ ] Tests pass successfully

