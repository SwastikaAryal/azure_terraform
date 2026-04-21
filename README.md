# Azure Storage Account Module (v2)

## Overview

This module provisions a hardened Azure Storage Account using the BMW corporate storage module (`terraform-azure-bmw-storage v5.0.4`) as the base, and layers on lifecycle management policies, monitoring/alerting, and Microsoft Defender for Storage.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  v2/storage_account (this module)                       │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │  module.bmw_storage_account (v5.0.4)              │  │
│  │  ├── azurerm_storage_account                      │  │
│  │  ├── azurerm_private_endpoint (blob, table, queue)│  │
│  │  ├── azurerm_user_assigned_identity               │  │
│  │  ├── azurerm_storage_account_customer_managed_key  │  │
│  │  └── azurerm_monitor_diagnostic_setting (x5)      │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  azurerm_storage_management_policy       (conditional)  │
│  azurerm_monitor_action_group            (conditional)  │
│  azurerm_monitor_metric_alert            (conditional)  │
│  azurerm_security_center_subscription_pricing (cond.)   │
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

- Terraform `>= 1.11.4`
- AzureRM provider `>= 4.27.0`
- **FPC Owner Role** on the target subscription (required by the BMW storage module)
- Access to the BMW GitHub Enterprise (`atc-github.azure.cloud.bmw`)
- An existing resource group, VNet, and subnet for private endpoints
- **Provider configuration**: add `storage_use_azuread = true` to the azurerm provider block if `shared_access_key_enabled` is set to `false`

## Usage

```hcl
module "storage_account" {
  source = "../../modules/v2/storage_account"

  global_config = {
    env             = "dev"
    customer_prefix = "cgbp"
    product_id      = "SWP-0815"
    appd_id         = "APPD-304118"
    app_name        = "sto10weu"
    costcenter      = "0815"
  }

  cloud_region        = "eastus"
  resource_group_name = "rg-app-dev"

  private_link_endpoint_subnet = {
    name                 = "snet-pe"
    resource_group_name  = "rg-network"
    virtual_network_name = "vnet-spoke"
  }

  # Storage
  account_tier             = "Standard"
  account_replication_type = "GRS"
  account_kind             = "StorageV2"
  custom_name_suffix       = "data"

  # Security
  public_network_access_enabled   = false
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  enable_defender_for_storage     = true

  # Tags
  tags = {
    Environment = "Dev"
    ManagedBy   = "Terraform"
  }
}
```

## Input Variables

### Required

| Name | Type | Description |
|------|------|-------------|
| `global_config` | `any` | BMW global configuration object (env, customer_prefix, product_id, appd_id, app_name, costcenter) |
| `cloud_region` | `string` | Azure region for deployment (e.g. `eastus`) |
| `resource_group_name` | `string` | Target resource group name |
| `private_link_endpoint_subnet` | `object` | Subnet details for private endpoints — requires `name`, `resource_group_name`, `virtual_network_name` |
| `create_private_endpoint` | `bool` | Whether to create private endpoints |

### Storage Account

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `account_tier` | `string` | `"Standard"` | Storage account tier (`Standard` or `Premium`) |
| `account_replication_type` | `string` | `"GRS"` | Replication type (`LRS`, `GRS`, `RAGRS`, `ZRS`, `GZRS`, `RAGZRS`) |
| `account_kind` | `string` | `"StorageV2"` | Account kind (`StorageV2`, `BlobStorage`, `BlockBlobStorage`, etc.) |
| `custom_name_suffix` | `string` | `""` | Custom suffix appended to the generated storage account name |
| `tags` | `map(string)` | `{}` | Tags applied to all resources |

### Security

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `public_network_access_enabled` | `bool` | `false` | Enable public network access to the storage account |
| `shared_access_key_enabled` | `bool` | `false` | Allow shared key authorization. Set to `false` to enforce Azure AD only |
| `default_to_oauth_authentication` | `bool` | `true` | Default to Azure AD auth in the Azure Portal |
| `enable_defender_for_storage` | `bool` | `false` | Enable Microsoft Defender for Storage (subscription-level resource) |

### Customer Managed Key (CMK)

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `enable_cmk` | `bool` | `false` | Enable CMK encryption via the BMW module's built-in CMEK key vault |
| `cmk_key_name` | `string` | `null` | Key Vault key name for CMK (required when `enable_cmk = true`) |
| `cmk_key_vault_id` | `string` | `null` | Key Vault resource ID (required when `enable_cmk = true`) |
| `cmk_user_assigned_identity_id` | `string` | `null` | User-assigned managed identity ID for CMK access |

### Diagnostics

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `create_diagnostic_settings` | `bool` | `false` | Enable diagnostic settings (blob, queue, table, file logs) |
| `log_analytics_workspace_id` | `string` | `null` | Log Analytics Workspace ID (required when diagnostics enabled) |

### Storage Properties

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `blob_properties` | `any` | `{}` | Blob versioning, change feed, retention policies |
| `queue_properties` | `any` | `{}` | Queue logging and metrics configuration. Use `null` to skip |

### Network

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `allowed_ips` | `list(string)` | `[]` | IP addresses/CIDRs allowed through the storage firewall |
| `allowed_subnet_ids` | `list(string)` | `[]` | Subnet IDs allowed through the storage firewall |

### Lifecycle Management

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `storage_management_policy` | `object` | `{ rules = [] }` | Blob lifecycle rules for tiering, archival, and deletion |

### Monitoring

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `monitoring` | `object` | `null` | Action group and metric alert configuration. Set `enabled = true` to activate |

## Resources Created

| Resource | Condition | Description |
|----------|-----------|-------------|
| `module.bmw_storage_account` | Always | BMW storage account with private endpoints, identity, and optional CMK |
| `azurerm_storage_management_policy` | `storage_management_policy.rules` is non-empty | Blob lifecycle rules (cool tier, archive, delete) |
| `azurerm_monitor_action_group` | `monitoring.enabled = true` | Alert notification channel (email, webhook) |
| `azurerm_monitor_metric_alert` | `monitoring.enabled = true` | Metric-based alert scoped to the storage account |
| `azurerm_security_center_subscription_pricing` | `enable_defender_for_storage = true` | Microsoft Defender for Storage (Standard tier, subscription-level) |

## Hardened Defaults

The module applies these security settings through the BMW base module:

- **TLS 1.2 minimum** enforced
- **HTTPS only** traffic
- **Infrastructure encryption** enabled
- **Network rules** default to `Deny` with `AzureServices` bypass
- **SAS policy** with 90-day expiration and audit logging
- **Microsoft routing** for StorageV2 accounts
- **Azure Files authentication** via Microsoft Entra Kerberos (AADKERB)
- **Private endpoints** for blob, table, and queue sub-resources
- **User-assigned managed identity** created automatically

## Testing

Place `storage_account.tftest.hcl` in the `tests/` directory.

```bash
# Run tests
terraform test -chdir=terraform/modules/v2/storage_account
```

> **Note**: `azurerm_security_center_subscription_pricing` is a subscription-level singleton. If Defender for Storage is already enabled on the subscription, the test should set `enable_defender_for_storage = false` to avoid import conflicts.

> **Note**: When running apply tests with `shared_access_key_enabled = false`, the azurerm provider must have `storage_use_azuread = true` configured, otherwise data plane polling will fail with a 403.

## File Structure

```
terraform/modules/v2/storage_account/
├── main.tf                # Module calls, resources
├── variables.tf           # Input variable definitions
├── outputs.tf             # Output values
├── providers.tf           # Provider version constraints
├── terraform.tfvars       # Example variable values
└── tests/
    └── storage_account.tftest.hcl   # Terraform native tests
```

## Important Notes

1. **FPC Owner Role** is required to deploy the storage account through the BMW module.
2. **Defender for Storage** (`azurerm_security_center_subscription_pricing`) operates at the subscription level — enabling it in one module affects the entire subscription.
3. **Private endpoints** are always created for blob, table, and queue. DNS registration is handled externally.
4. **CMK encryption** requires a pre-existing Key Vault and user-assigned identity when using external keys (`enable_cmk = true` with explicit IDs), or the module can create its own via the BMW module's built-in CMEK feature.
5. **Queue properties** should be set to `null` (not `{}`) when not needed, to avoid invalid XML errors from the Azure API.
