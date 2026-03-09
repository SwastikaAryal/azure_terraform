# Azure Backup Vault - Copy & Paste Security Fixes

## ✂️ Ready-to-Use Code Snippets

Use these snippets to quickly implement security fixes. Simply copy and paste into your Terraform files.

---

## 1️⃣ ENABLE CMK ENCRYPTION

### Add to variables.tf

```hcl
# Customer-Managed Key (CMK) Configuration
variable "enable_customer_managed_key" {
  type        = bool
  description = "Enable customer-managed keys for encryption"
  default     = false
}

variable "key_vault_id" {
  type        = string
  description = "Key Vault ID for encryption keys"
  default     = null
}

variable "key_vault_key_name" {
  type        = string
  description = "Name of the key in Key Vault"
  default     = null
}
```

### Add to main.tf

```hcl
# Create user-assigned identity for CMK
resource "azurerm_user_assigned_identity" "vault_cmk" {
  count               = var.enable_customer_managed_key ? 1 : 0
  name                = "${module.common.names.resource_type["azurerm_data_protection_backup_vault"].name}-cmk"
  resource_group_name = var.resource_group_name
  location            = var.cloud_region
  tags                = module.common.tags
}

# Grant Key Vault permissions
resource "azurerm_key_vault_access_policy" "vault_cmk" {
  count       = var.enable_customer_managed_key ? 1 : 0
  key_vault_id = var.key_vault_id
  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = azurerm_user_assigned_identity.vault_cmk[0].principal_id

  key_permissions = ["Get", "Decrypt", "Encrypt", "WrapKey", "UnwrapKey"]
}

# Get current context
data "azurerm_client_config" "current" {}
```

### Update backup vault resource

```hcl
resource "azurerm_data_protection_backup_vault" "this" {
  name                = module.common.names.resource_type["azurerm_data_protection_backup_vault"].name
  resource_group_name = var.resource_group_name
  location            = var.cloud_region
  datastore_type      = var.datastore_type
  redundancy          = var.redundancy

  identity {
    type = "SystemAssigned"
    identity_ids = var.enable_customer_managed_key ? [
      azurerm_user_assigned_identity.vault_cmk[0].id
    ] : []
  }

  # CMK Encryption
  dynamic "encryption" {
    for_each = var.enable_customer_managed_key ? [1] : []
    content {
      key_vault_key_id = "${var.key_vault_id}/keys/${var.key_vault_key_name}"
      user_assigned_identity_id = azurerm_user_assigned_identity.vault_cmk[0].id
      infrastructure_encryption_enabled = true
    }
  }

  retention_duration_in_days = var.retention_duration_in_days
  soft_delete                = var.soft_delete
  tags                       = module.common.tags
  depends_on                 = [azurerm_key_vault_access_policy.vault_cmk]
}
```

---

## 2️⃣ DEPLOY PRIVATE ENDPOINTS

### Add to variables.tf

```hcl
variable "enable_private_endpoint" {
  type        = bool
  description = "Enable private endpoint for backup vault"
  default     = true
}

variable "virtual_network_id" {
  type        = string
  description = "Virtual network ID for private endpoint"
  default     = null
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for private endpoint"
  default     = null
}
```

### Add to main.tf

```hcl
# Private Endpoint
resource "azurerm_private_endpoint" "backup_vault" {
  count               = var.enable_private_endpoint ? 1 : 0
  name                = "${module.common.names.resource_type["azurerm_data_protection_backup_vault"].name}-pep"
  location            = var.cloud_region
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "${module.common.names.resource_type["azurerm_data_protection_backup_vault"].name}-psc"
    private_connection_resource_id = azurerm_data_protection_backup_vault.this.id
    subresource_names              = ["AzureBackup"]
    is_manual_connection           = false
  }
  tags = module.common.tags
}

# Private DNS Zone
resource "azurerm_private_dns_zone" "backup_vault" {
  count               = var.enable_private_endpoint ? 1 : 0
  name                = "privatelink.backup.azure.com"
  resource_group_name = var.resource_group_name
  tags                = module.common.tags
}

# DNS Zone Link
resource "azurerm_private_dns_zone_virtual_network_link" "backup_vault" {
  count                 = var.enable_private_endpoint ? 1 : 0
  name                  = "backup-vault-vnet-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.backup_vault[0].name
  virtual_network_id    = var.virtual_network_id
  tags                  = module.common.tags
}

# DNS A Record
resource "azurerm_private_dns_a_record" "backup_vault" {
  count               = var.enable_private_endpoint ? 1 : 0
  name                = azurerm_data_protection_backup_vault.this.name
  zone_name           = azurerm_private_dns_zone.backup_vault[0].name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.backup_vault[0].private_service_connection[0].private_ip_address]
}

# Management Lock
resource "azurerm_management_lock" "backup_vault_delete_lock" {
  name       = "backup-vault-delete-lock"
  scope      = azurerm_data_protection_backup_vault.this.id
  lock_level = "CanNotDelete"
  notes      = "Prevent deletion of backup vault"
}
```

---

## 3️⃣ ENFORCE SOFT DELETE & RETENTION

### Update variables.tf

```hcl
variable "soft_delete" {
  type        = string
  description = "Soft delete state. Values: AlwaysOn, On, Off"
  default     = "AlwaysOn"
  
  validation {
    condition     = contains(["AlwaysOn", "On", "Off"], var.soft_delete)
    error_message = "Must be AlwaysOn, On, or Off"
  }
}

variable "retention_duration_in_days" {
  type        = number
  description = "Soft delete retention in days (14-180)"
  default     = 30
  
  validation {
    condition     = var.retention_duration_in_days >= 14 && var.retention_duration_in_days <= 180
    error_message = "Must be between 14 and 180 days"
  }
}

variable "enforce_soft_delete_always_on" {
  type        = bool
  description = "Force AlwaysOn soft delete"
  default     = true
}
```

### Update main.tf

```hcl
resource "azurerm_data_protection_backup_vault" "this" {
  # ... existing config ...
  
  soft_delete = var.enforce_soft_delete_always_on ? "AlwaysOn" : var.soft_delete
  retention_duration_in_days = var.retention_duration_in_days
  
  # ... rest of config ...
}
```

---

## 4️⃣ IMPLEMENT LEAST PRIVILEGE ROLES

### Update variables.tf

```hcl
variable "backup_role_blob_storage" {
  type        = string
  description = "Role for blob storage (use 'Storage Account Backup Contributor')"
  default     = "Storage Account Backup Contributor"
  
  validation {
    condition     = contains(["", "Storage Account Backup Contributor"], var.backup_role_blob_storage)
    error_message = "Use 'Storage Account Backup Contributor', not 'Reader'"
  }
}

variable "backup_role_disks" {
  type        = string
  description = "Role for disks (use 'Disk Backup Reader')"
  default     = "Disk Backup Reader"
  
  validation {
    condition     = contains(["", "Disk Backup Reader", "Disk Snapshot Contributor"], var.backup_role_disks)
    error_message = "Use 'Disk Backup Reader', not 'Reader'"
  }
}

variable "backup_role_db" {
  type        = string
  description = "Role for PostgreSQL"
  default     = "PostgreSQL Flexible Server Long Term Retention Backup Role"
}
```

### Update role assignments in main.tf

```hcl
resource "azurerm_role_assignment" "blobs" {
  count = var.backup_role_blob_storage != "" ? length(var.backup_blob_storages) : 0
  
  scope              = var.backup_blob_storages[count.index]
  role_definition_name = var.backup_role_blob_storage
  principal_id       = azurerm_data_protection_backup_vault.this.identity[0].principal_id

  lifecycle {
    precondition {
      condition     = var.backup_role_blob_storage != "Reader"
      error_message = "Must use 'Storage Account Backup Contributor' for least privilege"
    }
  }
}

resource "azurerm_role_assignment" "disks" {
  count = var.backup_role_disks != "" ? length(var.backup_disks) : 0
  
  scope              = var.backup_disks[count.index]
  role_definition_name = var.backup_role_disks
  principal_id       = azurerm_data_protection_backup_vault.this.identity[0].principal_id

  lifecycle {
    precondition {
      condition     = !contains(["Reader"], var.backup_role_disks)
      error_message = "Must use 'Disk Backup Reader' for least privilege"
    }
  }
}
```

---

## 5️⃣ ENABLE DIAGNOSTIC SETTINGS

### Update variables.tf

```hcl
variable "enable_diagnostic_settings" {
  type        = bool
  description = "Enable diagnostic settings (CRITICAL for production)"
  default     = true
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Log Analytics workspace ID"
  default     = null
  
  validation {
    condition     = var.enable_diagnostic_settings ? var.log_analytics_workspace_id != null : true
    error_message = "log_analytics_workspace_id required when diagnostic settings enabled"
  }
}
```

### Update main.tf

```hcl
data "azurerm_monitor_diagnostic_categories" "backup_vault" {
  count       = var.enable_diagnostic_settings ? 1 : 0
  resource_id = azurerm_data_protection_backup_vault.this.id
}

resource "azurerm_monitor_diagnostic_setting" "backup_vault" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "${azurerm_data_protection_backup_vault.this.name}-diag"
  target_resource_id         = azurerm_data_protection_backup_vault.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id
  log_analytics_destination_type = "AzureDiagnostics"

  dynamic "enabled_log" {
    for_each = data.azurerm_monitor_diagnostic_categories.backup_vault[0].log_category_types
    content {
      category = enabled_log.value
      enabled  = true
    }
  }

  dynamic "enabled_metric" {
    for_each = data.azurerm_monitor_diagnostic_categories.backup_vault[0].metrics
    content {
      category = enabled_metric.value
      enabled  = true
    }
  }
}
```

---

## 6️⃣ ENABLE RESOURCE GUARD

### Already in variables.tf - Just enable

```hcl
variable "use_resource_guard" {
  type        = bool
  description = "Deploy Resource Guard for multi-user admin"
  default     = true  # Change from false to true
}

variable "vault_critical_operation_exclusion_list" {
  type        = list(string)
  description = "Operations excluded from resource guard protection"
  default     = ["getSecurityPIN"]  # Minimal list
}
```

---

## 📋 Complete Example Usage

```hcl
module "backup_vault" {
  source = "./"

  # Basic Configuration
  cloud_region        = "eastus"
  resource_group_name = "my-rg"

  global_config = {
    env         = "production"
    appd_id     = "backup-app"
    app_name    = "backup-vault"
  }

  # ============================================
  # SECURITY FIXES ENABLED
  # ============================================

  # Fix #1: Enable CMK Encryption
  enable_customer_managed_key = true
  key_vault_id                = azurerm_key_vault.this.id
  key_vault_key_name          = "backup-vault-key"

  # Fix #2: Enable Private Endpoints
  enable_private_endpoint    = true
  virtual_network_id         = azurerm_virtual_network.this.id
  subnet_id                  = azurerm_subnet.private.id

  # Fix #3: Enforce Soft Delete
  soft_delete                    = "AlwaysOn"
  retention_duration_in_days     = 90
  enforce_soft_delete_always_on  = true

  # Fix #4: Least Privilege Roles
  backup_role_blob_storage = "Storage Account Backup Contributor"
  backup_role_disks        = "Disk Backup Reader"
  backup_role_db           = "PostgreSQL Flexible Server Long Term Retention Backup Role"

  # Fix #5: Enable Audit Logging
  enable_diagnostic_settings = true
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  # Fix #6: Enable Resource Guard
  use_resource_guard = true
  vault_critical_operation_exclusion_list = ["getSecurityPIN"]

  # Backup Configuration
  backup_blob_storages                 = [azurerm_storage_account.this.id]
  backup_blob_storages_container_names = ["backups"]
  
  backup_disks = [azurerm_managed_disk.this.id]
  
  backup_dbs = [
    {
      server_id   = azurerm_postgresql_server.this.id
      database_id = azurerm_postgresql_database.this.id
    }
  ]

  # Retention Configuration
  default_retention_duration      = "P30D"
  backup_repeating_time_intervals = ["R/2024-01-01T03:00:00+00:00/P1D"]

  retention_rules = [
    {
      name     = "weekly"
      duration = "P7D"
      criteria = {
        absolute_criteria = "FirstOfWeek"
      }
      priority = 1
    },
    {
      name     = "monthly"
      duration = "P90D"
      criteria = {
        absolute_criteria = "FirstOfMonth"
      }
      priority = 2
    }
  ]

  tags = {
    Environment        = "Production"
    DataClassification = "Critical"
    BackupRequired     = "Yes"
  }
}
```

---

## 🧪 Test Your Implementation

```bash
# Copy test file
cp tftest.hcl ./

# Copy setup module
mkdir -p tests/setup
cp tests_setup_main.tf tests/setup/main.tf

# Run tests
terraform test

# Verbose output
terraform test -verbose
```

---

## ✅ Validation Script

```bash
#!/bin/bash
# validate_security.sh

echo "Checking Azure Backup Vault Security Configuration..."
echo ""

# Check CMK
echo "✓ CMK Encryption: "
terraform console -var-file="production.tfvars" <<< "var.enable_customer_managed_key"

# Check Private Endpoints
echo "✓ Private Endpoints: "
terraform console -var-file="production.tfvars" <<< "var.enable_private_endpoint"

# Check Soft Delete
echo "✓ Soft Delete: "
terraform console -var-file="production.tfvars" <<< "var.soft_delete"

# Check Retention Days
echo "✓ Retention Days: "
terraform console -var-file="production.tfvars" <<< "var.retention_duration_in_days"

# Check Roles
echo "✓ Blob Storage Role: "
terraform console -var-file="production.tfvars" <<< "var.backup_role_blob_storage"

echo "✓ Disk Backup Role: "
terraform console -var-file="production.tfvars" <<< "var.backup_role_disks"

echo "✓ DB Backup Role: "
terraform console -var-file="production.tfvars" <<< "var.backup_role_db"

# Check Diagnostics
echo "✓ Diagnostic Settings: "
terraform console -var-file="production.tfvars" <<< "var.enable_diagnostic_settings"

echo ""
echo "Security validation complete!"
```

---

## 🔗 Quick Links

- **Security Analysis:** SECURITY_ANALYSIS.md
- **Implementation Guide:** REMEDIATION_GUIDE.md
- **Tests:** tftest.hcl
- **Test Setup:** tests_setup_main.tf
- **Implementation Guide:** IMPLEMENTATION_GUIDE.md

---

**Ready to implement?** Start with snippet #1 (CMK), then #2 (Private Endpoints), then work through the rest!

