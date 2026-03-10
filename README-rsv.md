# terraform-azure-bmw-recovery-vault-enhanced

Terraform module for deploying Azure Recovery Services Vault in BMW cloud environments. Covers VM backup, file share backup, SQL/SAP HANA workload backup, managed disk snapshot-based backup (Data Protection), Azure Site Recovery for DR, manual disk snapshots, private endpoints, backup alerting, and diagnostic settings — all in a single module following BMW naming and tagging conventions.

---

## Features

- **Recovery Services Vault** with configurable SKU, redundancy, soft delete, and immutability
- **VM Backup** with daily/weekly/monthly/yearly retention policies
- **File Share Backup** with configurable schedules and retention
- **VM Workload Backup** for SQL Server and SAP HANA databases
- **Azure Site Recovery** for cross-region VM disaster recovery replication with network mapping
- **Data Protection Backup Vault** for managed disk snapshot-based backups
- **Manual Disk Snapshots** (incremental or full) for point-in-time recovery
- **Customer Managed Key (CMK)** encryption with optional infrastructure double-encryption
- **Private Endpoint** support for both Azure Backup and ASR
- **Azure Monitor Alerts** for backup and restore health failures
- **Diagnostic Settings** to Log Analytics (guarded — only created when workspace ID is provided)
- User-Assigned or System-Assigned Managed Identity
- BMW Cloud Commons naming and tagging

---

## Usage

### Basic RSV with VM backup

```hcl
module "recovery_vault" {
  source = "git::https://atc-github.azure.cloud.bmw/cgbp/terraform-azure-bmw-recovery-vault.git?ref=<version>"

  cloud_region = "westeurope"

  global_config = {
    env      = "prod"
    appd_id  = "appd-001"
    app_name = "myapp"
  }

  resource_group_name = "rg-myapp-prod"
  sku                 = "Standard"
  soft_delete_enabled = true
  storage_mode_type   = "GeoRedundant"

  vms = {
    "vm-app-01" = {
      vm_id = "/subscriptions/<sub-id>/resourceGroups/rg-myapp-prod/providers/Microsoft.Compute/virtualMachines/vm-app-01"
      backup = {
        frequency = "Daily"
        time      = "02:00"
      }
      retention_daily = 30
    }
  }
}
```

### RSV with Site Recovery

```hcl
module "recovery_vault" {
  source = "git::https://atc-github.azure.cloud.bmw/cgbp/terraform-azure-bmw-recovery-vault.git?ref=<version>"

  cloud_region        = "westeurope"
  resource_group_name = "rg-myapp-prod"

  global_config = {
    env      = "prod"
    appd_id  = "appd-001"
    app_name = "myapp"
  }

  sku               = "Standard"
  storage_mode_type = "GeoRedundant"

  enable_site_recovery         = true
  site_recovery_target_region  = "northeurope"
  site_recovery_source_network_id = "/subscriptions/<sub-id>/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-westeurope"
  site_recovery_target_network_id = "/subscriptions/<sub-id>/resourceGroups/rg-network-dr/providers/Microsoft.Network/virtualNetworks/vnet-northeurope"

  site_recovery_replicated_vms = {
    "vm-app-01" = {
      source_vm_id               = "/subscriptions/<sub-id>/resourceGroups/rg-myapp-prod/providers/Microsoft.Compute/virtualMachines/vm-app-01"
      target_resource_group_id   = "/subscriptions/<sub-id>/resourceGroups/rg-myapp-dr"
      target_availability_zone   = "1"
      managed_disk = [
        {
          disk_id                    = "/subscriptions/<sub-id>/resourceGroups/rg-myapp-prod/providers/Microsoft.Compute/disks/vm-app-01-osdisk"
          staging_storage_account_id = "/subscriptions/<sub-id>/resourceGroups/rg-myapp-prod/providers/Microsoft.Storage/storageAccounts/stsiterecovery"
          target_disk_type           = "Premium_LRS"
        }
      ]
    }
  }
}
```

### Manual disk snapshot before maintenance

```hcl
module "recovery_vault" {
  source = "..."

  cloud_region        = "westeurope"
  resource_group_name = "rg-myapp-prod"
  global_config       = { ... }

  disk_snapshots = {
    "os-disk-before-patch" = {
      source_disk_id = "/subscriptions/<sub-id>/resourceGroups/rg-myapp-prod/providers/Microsoft.Compute/disks/vm-osdisk"
      disk_size_gb   = 128
      incremental    = true
    }
  }
}
```

---

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.3 |
| azurerm | >= 4.31 |

---

## Input Variables

### Required

| Variable | Type | Description |
|----------|------|-------------|
| `cloud_region` | `string` | Azure region (e.g. `westeurope`) |
| `global_config` | `object` | BMW global config — `env`, `appd_id`, `app_name` are required |
| `resource_group_name` | `string` | Resource group to deploy the vault into |

### Vault Core

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `sku` | `string` | `Standard` | Vault SKU: `Standard` or `RS0` |
| `soft_delete_enabled` | `bool` | `true` | Enable soft delete (prevents deletion for 14 days) |
| `storage_mode_type` | `string` | `GeoRedundant` | `LocallyRedundant`, `ZoneRedundant`, or `GeoRedundant` |
| `cross_region_restore_enabled` | `bool` | `false` | Enable cross-region restore (requires `GeoRedundant`) |
| `public_network_access_enabled` | `bool` | `false` | Allow public network access to vault |
| `immutability` | `string` | `null` | `Locked`, `Unlocked`, or `Disabled` |
| `backup_timezone` | `string` | `UTC` | Timezone for all backup schedules |
| `classic_vmware_replication_enabled` | `bool` | `false` | Enable classic VMware replication experience |

### Identity

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `use_managed_identity` | `bool` | `false` | Create User-Assigned Managed Identity for the vault |
| `use_system_assigned_identity` | `bool` | `false` | Enable System-Assigned Identity |
| `identity_ids` | `list(string)` | `[]` | List of existing UAI IDs to assign to the vault |

### Encryption (CMK)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `encrypt_vault` | `bool` | `false` | Encrypt vault with Customer Managed Key |
| `key_id` | `string` | `null` | Key Vault key ID for CMK encryption |
| `infrastructure_encryption_enabled` | `bool` | `false` | Enable double encryption (infrastructure layer) |
| `key_user_assigned_identity_id` | `string` | `null` | UAI ID for key access |
| `key_use_system_assigned_identity` | `bool` | `false` | Use System-Assigned Identity for key access |

### VM Backup

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `vms` | `map(object)` | `{}` | Map of VMs to back up. Key is a logical name |

Each VM entry supports:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `vm_id` | `string` | — | Full resource ID of the VM (required) |
| `backup.frequency` | `string` | — | `Daily`, `Weekly`, or `Hourly` |
| `backup.time` | `string` | — | Schedule time e.g. `02:00` |
| `retention_daily` | `number` | `90` | Daily retention in days |
| `retention_weekly` | `number` | `null` | Weekly retention in weeks |
| `retention_monthly` | `number` | `null` | Monthly retention in months |
| `retention_yearly` | `number` | `null` | Yearly retention in years |
| `include_disk_luns` | `list(string)` | `null` | LUNs to include |
| `exclude_disk_luns` | `list(string)` | `null` | LUNs to exclude |
| `instant_restore_retention_days` | `number` | `5` | Instant restore snapshot retention |

### File Share Backup

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `storage_accounts` | `map(object)` | `{}` | Map of storage accounts and file shares to protect |

### VM Workload Backup (SQL / SAP HANA)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `vm_workloads` | `map(object)` | `{}` | Map of workload backup policies for SQL Server or SAP HANA |

### Azure Site Recovery

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_site_recovery` | `bool` | `false` | Enable ASR cross-region replication |
| `site_recovery_target_region` | `string` | `null` | Target (DR) Azure region |
| `site_recovery_rpo_retention_minutes` | `number` | `1440` | Recovery point retention in minutes |
| `site_recovery_app_consistent_snapshot_frequency_minutes` | `number` | `240` | App-consistent snapshot frequency |
| `site_recovery_auto_update_extension` | `bool` | `true` | Auto-update ASR mobility extension |
| `site_recovery_automation_account_id` | `string` | `null` | Automation account for auto-updates |
| `site_recovery_source_network_id` | `string` | `null` | Source VNet ID for network mapping |
| `site_recovery_target_network_id` | `string` | `null` | Target VNet ID for failover |
| `site_recovery_replicated_vms` | `map(object)` | `{}` | VMs to replicate via ASR |

### Disk Backup (Data Protection)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_disk_backup` | `bool` | `false` | Enable Data Protection Backup Vault for managed disks |
| `disk_backup_redundancy` | `string` | `LocallyRedundant` | Vault redundancy: `LocallyRedundant`, `ZoneRedundant`, `GeoRedundant` |
| `disk_backup_policies` | `map(object)` | `{}` | Snapshot backup policies for managed disks |
| `disk_backup_instances` | `map(object)` | `{}` | Managed disks to register for backup |
| `disk_backup_snapshot_resource_groups` | `map(string)` | `{}` | Resource group IDs for snapshot storage |

### Manual Disk Snapshots

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `disk_snapshots` | `map(object)` | `{}` | Disks to snapshot. Key is a logical name |

Each snapshot entry supports:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `source_disk_id` | `string` | — | Resource ID of the source managed disk (required) |
| `disk_size_gb` | `number` | `null` | Override disk size in snapshot |
| `incremental` | `bool` | `true` | Use incremental snapshot (cost-effective) |
| `encryption_enabled` | `bool` | `false` | Apply CMK encryption to snapshot |
| `disk_encryption_key_secret_url` | `string` | `null` | Key Vault secret URL (required when encryption enabled) |
| `disk_encryption_key_vault_id` | `string` | `null` | Key Vault resource ID (required when encryption enabled) |

### Private Endpoint

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_private_endpoint` | `bool` | `false` | Create private endpoint for the vault |
| `private_endpoint_subnet_id` | `string` | `null` | Subnet ID for the private endpoint |
| `private_dns_zone_ids` | `list(string)` | `[]` | DNS zone IDs for Azure Backup private endpoint |
| `private_dns_zone_ids_asr` | `list(string)` | `[]` | DNS zone IDs for ASR private endpoint |

### Alerting

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `monitoring` | `object` | Both `true` | Built-in Azure Monitor alert settings |
| `enable_backup_alerts` | `bool` | `false` | Enable metric alerts for backup/restore failures |
| `backup_alert_action_group_ids` | `list(string)` | `[]` | Action Group IDs for alert notifications |

### Diagnostics

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_diagnostic_settings` | `bool` | `true` | Enable diagnostic settings (**requires `log_analytics_workspace_id`**) |
| `log_analytics_workspace_id` | `string` | `null` | Log Analytics workspace resource ID |

> **Note:** `enable_diagnostic_settings = true` has no effect when `log_analytics_workspace_id` is `null`. The diagnostic setting and its data source are only created when both conditions are met.

---

## Outputs

| Output | Description |
|--------|-------------|
| `recovery_services_vault_id` | Resource ID of the Recovery Services Vault |
| `recovery_services_vault_name` | Name of the Recovery Services Vault |
| `resource_group_name` | Resource group name |
| `recovery_services_vault_identity` | Identity block (principal_id, tenant_id) |
| `vm_backup_policy_ids` | Map of VM backup policy IDs |
| `protected_vm_ids` | Map of protected VM resource IDs |
| `file_share_backup_policy_ids` | Map of file share backup policy IDs |
| `workload_backup_policy_ids` | Map of workload backup policy IDs (SQL/SAP HANA) |
| `site_recovery_fabric_primary_id` | Primary Site Recovery fabric ID |
| `site_recovery_fabric_secondary_id` | Secondary (DR) Site Recovery fabric ID |
| `site_recovery_replication_policy_id` | Replication policy ID |
| `site_recovery_container_mapping_id` | Protection container mapping ID |
| `site_recovery_replicated_vm_ids` | Map of replicated VM IDs |
| `data_protection_backup_vault_id` | Data Protection Backup Vault ID |
| `data_protection_backup_vault_identity` | Data Protection Vault identity |
| `disk_backup_policy_ids` | Map of disk backup policy IDs |
| `disk_backup_instance_ids` | Map of disk backup instance IDs |
| `disk_snapshot_ids` | Map of manual disk snapshot IDs |
| `private_endpoint_id` | Private endpoint resource ID |
| `private_endpoint_ip` | Private IP address of the private endpoint |

---

## Known Issues & Fixes Applied

### `encryption_settings` block (azurerm >= 3.x)

The `enabled` argument was removed from `azurerm_snapshot.encryption_settings` in the azurerm provider v3+. The block now requires a `disk_encryption_key` sub-block when present. This module uses a `dynamic` block to skip encryption entirely when `encryption_enabled = false`:

```hcl
# Safe — skipped when encryption_enabled = false
dynamic "encryption_settings" {
  for_each = each.value.encryption_enabled && each.value.disk_encryption_key_secret_url != null ? [1] : []
  content {
    disk_encryption_key {
      secret_url      = each.value.disk_encryption_key_secret_url
      source_vault_id = each.value.disk_encryption_key_vault_id
    }
  }
}
```

### Diagnostic settings without workspace ID

`azurerm_monitor_diagnostic_setting` requires at least one destination. When `log_analytics_workspace_id = null`, the resource would fail with `Missing required argument`. Both the `data` source and the `resource` are guarded:

```hcl
count = var.enable_diagnostic_settings && var.log_analytics_workspace_id != null ? 1 : 0
```

---

## Testing

```bash
# Plan only
terraform test -filter=run.rsv_basic_plan

# Full test suite (requires Azure credentials)
terraform test
```

See `rsv_tftest.hcl` for test definitions covering basic vault creation, VM backup policy, disk snapshots without encryption, and full apply verification.
