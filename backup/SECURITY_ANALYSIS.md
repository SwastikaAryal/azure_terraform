# Security Analysis Report - Azure Backup Vault Terraform Module

## Executive Summary
This document outlines critical and high-priority security vulnerabilities found in the Terraform Azure Backup Vault module and provides remediation guidance.

---

## Critical Security Vulnerabilities

### 1. **Insufficient Encryption Configuration**
**Severity**: CRITICAL  
**CWE**: CWE-327 (Use of a Broken or Risky Cryptographic Algorithm)

#### Issue
The backup vault lacks explicit encryption configuration. While Azure provides default encryption, the module doesn't enforce customer-managed keys (CMK) for sensitive backup data.

#### Current Code
```hcl
resource "azurerm_data_protection_backup_vault" "this" {
  name                = module.common.names.resource_type["azurerm_data_protection_backup_vault"].name
  resource_group_name = var.resource_group_name
  location            = var.cloud_region
  datastore_type      = var.datastore_type
  redundancy          = var.redundancy
  # ... missing encryption configuration
}
```

#### Risk
- Backups encrypted with Microsoft-managed keys only
- No control over encryption key management
- Compliance failures for regulated workloads (HIPAA, PCI-DSS, SOC2)
- Cannot meet organization's encryption policy requirements

#### Fix
```hcl
# Add to variables.tf
variable "enable_customer_managed_key" {
  type        = bool
  description = "Enable customer-managed keys for backup vault encryption"
  default     = false
}

variable "key_vault_id" {
  type        = string
  description = "Key Vault ID for customer-managed encryption keys"
  default     = null
}

# Update main.tf
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
  soft_delete                = var.soft_delete

  # Add encryption configuration
  dynamic "encryption" {
    for_each = var.enable_customer_managed_key ? [1] : []
    content {
      key_vault_key_id = var.key_vault_id
      user_assigned_identity_id = azurerm_user_assigned_identity.vault_cmk[0].id
    }
  }

  tags = module.common.tags
}

# Add user-assigned identity for CMK
resource "azurerm_user_assigned_identity" "vault_cmk" {
  count               = var.enable_customer_managed_key ? 1 : 0
  name                = "${module.common.names.resource_type["azurerm_data_protection_backup_vault"].name}-cmk-identity"
  resource_group_name = var.resource_group_name
  location            = var.cloud_region

  tags = module.common.tags
}

# Grant Key Vault access
resource "azurerm_key_vault_access_policy" "vault_cmk" {
  count       = var.enable_customer_managed_key ? 1 : 0
  key_vault_id = var.key_vault_id

  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = azurerm_user_assigned_identity.vault_cmk[0].principal_id

  key_permissions = [
    "Get",
    "WrapKey",
    "UnwrapKey"
  ]
}
```

---

### 2. **Missing Public Network Access Control**
**Severity**: CRITICAL  
**CWE**: CWE-200 (Exposure of Sensitive Information to an Unauthorized Actor)

#### Issue
No network access controls are configured for the backup vault. It's exposed to the internet by default.

#### Current Code
The backup vault is created without any network security group (NSG) rules or private endpoint configuration.

#### Risk
- Backup vault accessible from anywhere on the internet
- Potential for unauthorized access attempts
- DoS attacks possible
- Data exfiltration risk
- Non-compliance with zero-trust security model

#### Fix
```hcl
# Add to variables.tf
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

variable "allowed_ip_ranges" {
  type        = list(string)
  description = "List of allowed IP ranges for public access (if enabled)"
  default     = []
}

# Add to main.tf
# Private Endpoint for Backup Vault
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

# Private DNS Zone for backup vault
resource "azurerm_private_dns_zone" "backup_vault" {
  count               = var.enable_private_endpoint ? 1 : 0
  name                = "privatelink.backup.azure.com"
  resource_group_name = var.resource_group_name

  tags = module.common.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "backup_vault" {
  count                 = var.enable_private_endpoint ? 1 : 0
  name                  = "backup-vault-vnet-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.backup_vault[0].name
  virtual_network_id    = var.virtual_network_id
}

resource "azurerm_private_dns_a_record" "backup_vault" {
  count               = var.enable_private_endpoint ? 1 : 0
  name                = azurerm_data_protection_backup_vault.this.name
  zone_name           = azurerm_private_dns_zone.backup_vault[0].name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.backup_vault[0].private_service_connection[0].private_ip_address]
}
```

---

### 3. **Weak Soft Delete Configuration**
**Severity**: HIGH  
**CWE**: CWE-434 (Unrestricted Upload of File with Dangerous Type)

#### Issue
Default soft delete is set to "On" but can be disabled. No enforcement of strong soft delete policies.

#### Current Code
```hcl
variable "soft_delete" {
  type        = string
  description = "The state of soft delete for this Backup Vault. Possible values are AlwaysOn, Off and On. Defaults to On."
  default     = "On"
}
```

#### Risk
- Soft delete can be disabled, allowing immediate permanent deletion
- Ransomware can permanently delete backups without recovery option
- Insufficient protection against malicious operations
- Default retention period of 14 days is too short for recovery

#### Fix
```hcl
# Update variables.tf
variable "soft_delete" {
  type        = string
  description = "The state of soft delete for this Backup Vault. Possible values are AlwaysOn, Off and On."
  default     = "AlwaysOn"
  
  validation {
    condition     = contains(["AlwaysOn", "On", "Off"], var.soft_delete)
    error_message = "soft_delete must be one of: AlwaysOn, On, Off"
  }
}

variable "retention_duration_in_days" {
  type        = number
  description = "The soft delete retention duration for this Backup Vault. Possible values are between 14 and 180."
  default     = 30  # Increased from 14 to 30 days
  
  validation {
    condition     = var.retention_duration_in_days >= 14 && var.retention_duration_in_days <= 180
    error_message = "retention_duration_in_days must be between 14 and 180"
  }
}

# Add to main.tf - enforce AlwaysOn in production
variable "enforce_soft_delete_always_on" {
  type        = bool
  description = "Enforce AlwaysOn soft delete policy regardless of input"
  default     = true
}

# Update resource
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
  soft_delete                = var.enforce_soft_delete_always_on ? "AlwaysOn" : var.soft_delete

  tags = module.common.tags
}
```

---

### 4. **Overly Permissive Role Assignments**
**Severity**: HIGH  
**CWE**: CWE-639 (Authorization Bypass Through User-Controlled Key)

#### Issue
Role assignments use overly broad built-in roles like "Reader" for backup operations, violating principle of least privilege.

#### Current Code
```hcl
variable "backup_role_disks" {
  type        = string
  description = "Role to allow accessing the Disks for backup. Set to `\"\"` skip role assignment"
  default     = "Reader"  # Too broad!
}

variable "backup_role_db" {
  type        = string
  description = "Role to allow accessing the Postgresql databases for backup. Set to `\"\"` skip role assignment"
  default     = "Reader"  # Too broad!
}
```

#### Risk
- Reader role grants excessive permissions
- Backup vault can access resources beyond its scope
- Privilege escalation opportunities
- Violation of least privilege principle
- Potential lateral movement by compromised backup service

#### Fix
```hcl
# Update variables.tf
variable "backup_role_disks" {
  type        = string
  description = "Role to allow accessing the Disks for backup. Recommended: 'Disk Snapshot Contributor' or 'Disk Backup Reader'"
  default     = "Disk Backup Reader"
  
  validation {
    condition     = contains(["", "Disk Backup Reader", "Disk Snapshot Contributor", "Reader"], var.backup_role_disks)
    error_message = "backup_role_disks must be one of: 'Disk Backup Reader', 'Disk Snapshot Contributor', 'Reader', or empty string"
  }
}

variable "backup_role_db" {
  type        = string
  description = "Role to allow accessing the Postgresql databases for backup. Recommended: 'PostgreSQL Flexible Server Long Term Retention Backup Role'"
  default     = "PostgreSQL Flexible Server Long Term Retention Backup Role"
  
  validation {
    condition     = contains(["", "PostgreSQL Flexible Server Long Term Retention Backup Role", "Reader"], var.backup_role_db)
    error_message = "backup_role_db must be one of: 'PostgreSQL Flexible Server Long Term Retention Backup Role' or empty string"
  }
}

# Add data source to get current principal info
data "azurerm_client_config" "current" {}

# Update role assignments with better defaults
resource "azurerm_role_assignment" "disks" {
  count = var.backup_role_disks != "" ? length(var.backup_disks) : 0

  scope              = var.backup_disks[count.index]
  role_definition_name = var.backup_role_disks
  principal_id       = azurerm_data_protection_backup_vault.this.identity[0].principal_id

  # Add condition scope for additional security
  lifecycle {
    precondition {
      condition     = var.backup_role_disks == "" || contains(["Disk Backup Reader", "Disk Snapshot Contributor"], var.backup_role_disks)
      error_message = "Using 'Reader' role is not recommended. Use 'Disk Backup Reader' or 'Disk Snapshot Contributor' instead."
    }
  }
}
```

---

### 5. **Missing Access Control and Audit Logging**
**Severity**: HIGH  
**CWE**: CWE-778 (Insufficient Logging)

#### Issue
No Azure Policy or Audit logging enforcement for backup vault operations.

#### Current Code
- Diagnostic settings are optional (default = false)
- No alerts on suspicious activities
- No Azure Policy enforcement

#### Risk
- Unauthorized operations not tracked
- Compliance violations undetected
- No forensic trail for incident response
- Inability to detect backup tampering
- Failed compliance audits

#### Fix
```hcl
# Add to variables.tf
variable "enable_diagnostic_settings" {
  type        = bool
  description = "Enables the diagnostic settings for backup vault (STRONGLY RECOMMENDED for production)"
  default     = true  # Changed from false to true
}

variable "enable_backup_vault_policy" {
  type        = bool
  description = "Enable Azure Policy for backup vault security compliance"
  default     = true
}

variable "audit_alerts_enabled" {
  type        = bool
  description = "Enable email alerts for suspicious vault activities"
  default     = true
}

variable "alert_email_recipients" {
  type        = list(string)
  description = "Email addresses for security alerts"
  default     = []
}

# Add to main.tf - Azure Policy for resource guard enforcement
resource "azurerm_management_lock" "vault_delete_lock" {
  name       = "backup-vault-delete-lock"
  scope      = azurerm_data_protection_backup_vault.this.id
  lock_level = "CanNotDelete"

  notes = "Prevent accidental or malicious deletion of backup vault"
}

# Add to outputs.tf
output "vault_id" {
  value       = azurerm_data_protection_backup_vault.this.id
  description = "The ID of the created backup vault"
}

output "vault_principal_id" {
  value       = azurerm_data_protection_backup_vault.this.identity[0].principal_id
  description = "The principal ID of the vault's managed identity"
}
```

---

### 6. **Missing Cross-Tenant Replication Controls**
**Severity**: MEDIUM  
**CWE**: CWE-285 (Improper Authorization)

#### Issue
No restrictions on cross-tenant or cross-region backup replication.

#### Current Code
```hcl
variable "redundancy" {
  type        = string
  description = "Specifies the backup storage redundancy. Possible values are `GeoRedundant` and `LocallyRedundant`"
  default     = "LocallyRedundant"
}
```

#### Risk
- GeoRedundant backups may replicate to untrusted regions
- No control over backup data location
- Potential data sovereignty violations
- Compliance issues with data residency requirements

#### Fix
```hcl
# Add to variables.tf
variable "allowed_replication_regions" {
  type        = list(string)
  description = "List of allowed regions for backup replication (for GeoRedundant)"
  default     = []  # User must explicitly specify
}

variable "redundancy" {
  type        = string
  description = "Specifies the backup storage redundancy. Possible values are `GeoRedundant` and `LocallyRedundant`"
  default     = "LocallyRedundant"
  
  validation {
    condition     = contains(["GeoRedundant", "LocallyRedundant"], var.redundancy)
    error_message = "redundancy must be either 'GeoRedundant' or 'LocallyRedundant'"
  }
}

# Add warning/validation
locals {
  warn_geo_redundant = var.redundancy == "GeoRedundant" && length(var.allowed_replication_regions) == 0 ? true : false
}

resource "null_resource" "geo_redundant_warning" {
  count = local.warn_geo_redundant ? 1 : 0
  provisioner "local-exec" {
    command = "echo 'WARNING: GeoRedundant backup enabled without specifying allowed_replication_regions'"
  }
}
```

---

### 7. **Missing Resource Tags Validation**
**Severity**: MEDIUM  
**CWE**: CWE-439 (Call to Function with Inconsistent Number of Arguments)

#### Issue
No validation of required tags, making resource governance impossible.

#### Fix
```hcl
# Add to variables.tf
variable "required_tags" {
  type        = list(string)
  description = "List of required tag keys that must be present"
  default     = ["Environment", "Owner", "CostCenter", "Application"]
}

# Add validation in main.tf
locals {
  required_tags_present = alltrue([for tag in var.required_tags : contains(keys(module.common.tags), tag)])
}

resource "null_resource" "validate_tags" {
  lifecycle {
    precondition {
      condition     = local.required_tags_present
      error_message = "Missing required tags. Required: ${join(", ", var.required_tags)}"
    }
  }
}
```

---

## Summary of Fixes

| Vulnerability | Severity | Fix Priority | Effort |
|--------------|----------|--------------|--------|
| Missing CMK encryption | CRITICAL | P0 | High |
| No network access controls | CRITICAL | P0 | High |
| Weak soft delete config | HIGH | P0 | Low |
| Overly permissive roles | HIGH | P1 | Medium |
| Missing audit logging | HIGH | P1 | Medium |
| No replication controls | MEDIUM | P2 | Low |
| Tag validation missing | MEDIUM | P2 | Low |

---

## Best Practices Recommendations

1. **Always use customer-managed keys** for sensitive data
2. **Enable private endpoints** by default in production
3. **Use AlwaysOn soft delete** with 30+ day retention
4. **Apply least privilege** role assignments
5. **Enable all diagnostic settings** with Log Analytics integration
6. **Implement Azure Policy** for continuous compliance
7. **Use management locks** to prevent vault deletion
8. **Tag all resources** consistently
9. **Enable resource guard** for multi-user admin scenarios
10. **Regular access reviews** for role assignments

