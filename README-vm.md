# terraform-azure-bmw-vm-enhanced

Terraform module for deploying Azure Virtual Machines (Linux or Windows) in BMW cloud environments. Supports full BMW naming/tagging conventions, managed identity, disk encryption, monitoring, backups, snapshots, and Site Recovery — all via a single root module.

---

## Features

- Deploy a **Linux VM** or **Windows VM** (mutually exclusive — enforced by precondition)
- Auto-generated VM name via BMW Cloud Commons naming convention
- **User-Assigned Managed Identity** (create new or use existing)
- **Network Interface** with optional static IP and accelerated networking
- **Network Security Group** with configurable inbound rules
- **OS Disk** with configurable size, caching, and storage type
- **Data Disks** with flexible `create_option` (Empty, Copy, Restore, FromImage, Upload), on-demand bursting, network access policies
- **Disk Encryption Set** with Azure Key Vault integration and auto key rotation
- **Azure Monitor Agent (AMA)** + Dependency Agent + Data Collection Rules for Linux and Windows
- **Diagnostic settings** to Log Analytics
- **OS disk and data disk snapshots** (incremental or full)
- **Recovery Services Vault** integration for VM backup
- **Azure Site Recovery** mobility service extension
- **Guest Configuration** extension for Azure Policy compliance
- **Disk Access** resource for private endpoint access to managed disks
- **VM Availability Alert** via Azure Monitor
- **Trusted Launch** support (Secure Boot + vTPM)
- **Spot VM** support with eviction policy
- Placement options: Availability Zone, Availability Set, Proximity Placement Group, Dedicated Host, Capacity Reservation

---

## Usage

### Linux VM (minimal)

```hcl
module "linux_vm" {
  source = "git::https://atc-github.azure.cloud.bmw/cgbp/terraform-azure-bmw-vm.git?ref=<version>"

  cloud_region = "westeurope"

  global_config = {
    env      = "dev"
    appd_id  = "appd-001"
    app_name = "myapp"
  }

  resource_group_name      = "rg-myapp-dev"
  vnet_resource_group_name = "rg-network-dev"
  virtual_network_name     = "vnet-dev"
  subnet_name              = "snet-app-dev"

  deploy_linux_vm                 = true
  deploy_windows_vm               = false
  admin_username                  = "azureadmin"
  disable_password_authentication = false
  admin_password                  = "P@ssw0rd1234!"

  linux_version = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}
```

### Windows VM with data disks and backup

```hcl
module "windows_vm" {
  source = "git::https://atc-github.azure.cloud.bmw/cgbp/terraform-azure-bmw-vm.git?ref=<version>"

  cloud_region = "westeurope"

  global_config = {
    env      = "prod"
    appd_id  = "appd-002"
    app_name = "myapp"
  }

  resource_group_name      = "rg-myapp-prod"
  vnet_resource_group_name = "rg-network-prod"
  virtual_network_name     = "vnet-prod"
  subnet_name              = "snet-app-prod"

  deploy_windows_vm = true
  deploy_linux_vm   = false
  admin_username    = "winadmin"
  admin_password    = "WinP@ssw0rd1234!"

  windows_version = {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }

  virtual_machine_size = "Standard_D4s_v5"
  disk_size_gb         = 128

  data_disks = [
    {
      name                 = "data-disk-01"
      storage_account_type = "Premium_LRS"
      disk_size_gb         = 256
      disk_caching         = "ReadOnly"
      create_option        = "Empty"
    }
  ]

  enable_recovery_service_vault = true
  vault_storage_mode_type       = "GeoRedundant"
}
```

---

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.3 |
| azurerm | >= 4.31 |
| random | >= 3.6 |
| time | >= 0.11 |

---

## Input Variables

### Required

| Variable | Type | Description |
|----------|------|-------------|
| `cloud_region` | `string` | Azure region (e.g. `westeurope`) |
| `global_config` | `object` | BMW global config — env, appd_id, app_name are required |
| `resource_group_name` | `string` | Resource group to deploy into |
| `vnet_resource_group_name` | `string` | Resource group containing the VNet |
| `virtual_network_name` | `string` | Name of the target VNet |
| `subnet_name` | `string` | Name of the target subnet |
| `deploy_linux_vm` | `bool` | Set `true` to deploy a Linux VM (mutually exclusive with `deploy_windows_vm`) |
| `deploy_windows_vm` | `bool` | Set `true` to deploy a Windows VM (mutually exclusive with `deploy_linux_vm`) |

### VM Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `virtual_machine_size` | `string` | `Standard_B2ms` | Azure VM SKU |
| `admin_username` | `string` | `azureadmin` | Local administrator username |
| `admin_password` | `string` | `null` | Admin password. Auto-generated if null |
| `random_password_length` | `number` | `32` | Length of auto-generated password |
| `computer_name` | `string` | `null` | OS hostname override |
| `custom_data` | `string` | `null` | cloud-init / custom data script (base64) |
| `allow_extension_operations` | `bool` | `true` | Allow VM extensions |
| `source_image_id` | `string` | `null` | Custom image ID (overrides image reference) |
| `availability_zone` | `string` | `null` | Availability zone (1, 2, or 3) |
| `priority` | `string` | `Regular` | VM priority: `Regular` or `Spot` |
| `eviction_policy` | `string` | `Deallocate` | Spot eviction policy: `Deallocate` or `Delete` |
| `max_price` | `number` | `-1` | Max hourly price for Spot VMs |

### Linux-Specific

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `linux_version` | `object` | BMW Ubuntu 22.04 | Publisher, offer, sku, version |
| `disable_password_authentication` | `bool` | `true` | Disable password auth (requires `admin_ssh_key`) |
| `admin_ssh_key` | `object` | `null` | SSH key object with `content` or `file_path` |
| `linux_patch_mode` | `string` | `ImageDefault` | Patch mode: `ImageDefault` or `AutomaticByPlatform` |

### Windows-Specific

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `windows_version` | `object` | Windows Server 2022 Datacenter | Publisher, offer, sku, version |
| `enable_automatic_updates` | `bool` | `true` | Enable automatic Windows updates |
| `windows_patch_mode` | `string` | `AutomaticByOS` | Patch mode |
| `windows_license_type` | `string` | `None` | License type (`None`, `Windows_Client`, `Windows_Server`) |
| `winrm_protocol` | `string` | `null` | WinRM protocol (`Http` or `Https`) |

### OS Disk

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `os_disk_name` | `string` | `null` | Custom OS disk name |
| `os_disk_storage_account_type` | `string` | `StandardSSD_LRS` | Storage type |
| `os_disk_caching` | `string` | `ReadWrite` | Caching mode |
| `disk_size_gb` | `number` | `127` | OS disk size in GB |
| `enable_os_disk_write_accelerator` | `bool` | `false` | Enable write accelerator |

### Data Disks

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `data_disks` | `list(object)` | `[]` | List of managed data disks to attach |

Each data disk object supports:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | `string` | — | Disk name (required) |
| `storage_account_type` | `string` | — | Storage type (required) |
| `disk_size_gb` | `number` | — | Size in GB (required) |
| `disk_caching` | `string` | — | Caching mode (required) |
| `create_option` | `string` | `Empty` | `Empty`, `Copy`, `Restore`, `FromImage`, `Upload` |
| `on_demand_bursting_enabled` | `bool` | `false` | Enable on-demand bursting |
| `network_access_policy` | `string` | `AllowAll` | `AllowAll`, `AllowPrivate`, `DenyAll` |
| `public_network_access_enabled` | `bool` | `true` | Allow public network access |
| `write_accelerator_enabled` | `bool` | `false` | Enable write accelerator |
| `trusted_launch_enabled` | `bool` | `false` | Enable Trusted Launch on disk |

### Networking

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `private_ip_address_allocation_type` | `string` | `Dynamic` | `Dynamic` or `Static` |
| `private_ip_address` | `string` | `null` | Static IP address (required when allocation is Static) |
| `ip_forwarding_enabled` | `bool` | `false` | Enable IP forwarding on NIC |
| `accelerated_networking_enabled` | `bool` | `false` | Enable accelerated networking |
| `use_existing_security_group` | `bool` | `false` | Attach existing NSG instead of creating one |
| `existing_network_security_group_id` | `string` | `null` | ID of existing NSG |
| `existing_nsg_name` | `string` | `null` | Name of existing NSG |
| `nsg_inbound_rules` | `list(object)` | `[]` | Custom NSG inbound rules (**blocked by BMW policy in sandbox**) |

### Identity & Encryption

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `create_user_assigned_identity` | `bool` | `true` | Create a new UAI for the VM |
| `uai_principal_name` | `string` | `null` | Name of existing UAI (when `create_user_assigned_identity = false`) |
| `uai_principal_rg_name` | `string` | `null` | Resource group of existing UAI |
| `managed_identity_type` | `string` | `UserAssigned` | Identity type |
| `enable_disk_encryption_set` | `bool` | `false` | Enable Disk Encryption Set with CMK |
| `key_vault_id` | `string` | `null` | Key Vault ID (required when encryption set is enabled) |
| `use_own_key_for_disk_encryption` | `bool` | `false` | Bring your own key instead of auto-generating |
| `disk_encryption_key_id` | `string` | `null` | Existing key ID when using own key |
| `auto_key_rotation_enabled` | `bool` | `false` | Auto-rotate encryption key |
| `enable_encryption_at_host` | `bool` | `false` | Enable host-level encryption |

### Monitoring

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_log_analytics_integration` | `bool` | `false` | Deploy AMA + DCR + diagnostic settings |
| `log_analytics_id` | `string` | `null` | Log Analytics workspace resource ID |
| `log_analytics_name` | `string` | `null` | Log Analytics workspace name |
| `enable_boot_diagnostics` | `bool` | `true` | Enable boot diagnostics |
| `storage_account_uri` | `string` | `null` | Storage account URI for boot diagnostics |

### Backup & Recovery

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_recovery_service_vault` | `bool` | `false` | Create and attach a Recovery Services Vault |
| `vault_sku` | `string` | `Standard` | RSV SKU |
| `vault_storage_mode_type` | `string` | `GeoRedundant` | Storage redundancy |
| `vault_soft_delete_enabled` | `bool` | `true` | Enable soft delete |
| `vault_cross_region_restore_enabled` | `bool` | `false` | Enable cross-region restore |
| `vault_vms` | `map(object)` | `null` | VM backup configuration map |
| `enable_os_disk_snapshot` | `bool` | `false` | Create OS disk snapshot |
| `enable_data_disk_snapshots` | `bool` | `false` | Create snapshots for all data disks |
| `snapshot_incremental` | `bool` | `true` | Use incremental snapshots |
| `enable_asr_extension` | `bool` | `false` | Install ASR mobility service extension |

### Advanced / Optional

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `secure_boot_enabled` | `bool` | `false` | Enable Secure Boot (Trusted Launch) |
| `vtpm_enabled` | `bool` | `false` | Enable vTPM (Trusted Launch) |
| `enable_guest_configuration` | `bool` | `false` | Install Guest Configuration extension |
| `enable_disk_private_access` | `bool` | `false` | Create Disk Access resource |
| `enable_vm_availability_alert` | `bool` | `false` | Create Monitor alert for VM availability |
| `vm_alert_action_group_ids` | `list(string)` | `[]` | Action Group IDs for availability alert |
| `availability_set_id` | `string` | `null` | Availability Set ID (conflicts with zone) |
| `proximity_placement_group_id` | `string` | `null` | Proximity Placement Group ID |
| `dedicated_host_id` | `string` | `null` | Dedicated Host ID |
| `enable_hibernation` | `bool` | `false` | Enable VM hibernation |
| `enable_termination_notification` | `bool` | `false` | Enable termination notification |
| `termination_notification_timeout` | `string` | `PT5M` | Notification timeout (ISO 8601) |
| `gallery_applications` | `list(object)` | `[]` | Gallery applications to install |
| `plan` | `object` | `null` | Marketplace plan block |

---

## Outputs

| Output | Description |
|--------|-------------|
| `virtual_machine_id` | Resource ID of the VM |
| `virtual_machine_name` | Generated name of the VM |
| `virtual_machine_private_ip_address` | Primary private IP |
| `virtual_machine_private_ip_addresses` | All private IPs |
| `virtual_machine_password` | Admin password (sensitive) |
| `virtual_machine_principal_id` | Principal ID of the managed identity |
| `virtual_machine_client_id` | Client ID of the managed identity |
| `virtual_machine_identity` | Full identity block |
| `virtual_machine_primary_nic_id` | Primary NIC resource ID |
| `network_id` | VNet resource ID |
| `primary_ip_configuration_name` | Name of primary IP configuration |
| `network_security_group_ids` | NSG resource IDs |
| `os_disk_name` | Name of the OS disk |
| `data_disks_ids` | List of data disk resource IDs |
| `data_disks_map` | Map of disk name → resource ID |
| `disk_encryption_set_id` | Disk Encryption Set resource ID |
| `disk_encryption_set_auto_key_rotation_enabled` | Whether auto key rotation is on |
| `disk_encryption_set_key_vault_key_url` | Key Vault key URL in use |
| `recovery_services_vault_id` | RSV resource ID |
| `recovery_services_vault_name` | RSV name |
| `os_disk_snapshot_id` | OS disk snapshot ID |
| `data_disk_snapshot_ids` | Map of disk name → snapshot ID |
| `disk_access_id` | Disk Access resource ID |
| `windows_data_collection_rule_id` | Windows DCR ID |
| `linux_data_collection_rule_id` | Linux DCR ID |

---

## Preconditions

The following are enforced at plan time and will fail fast with a clear error message:

| Check | Rule |
|-------|------|
| `only_allow_win_or_linux` | Exactly one of `deploy_linux_vm` or `deploy_windows_vm` must be `true` |
| `validate_availability` | `availability_zone` and `availability_set_id` are mutually exclusive |
| `validate_cross_region_restore` | Cross-region restore requires `vault_storage_mode_type = "GeoRedundant"` |
| `validate_disk_encryption` | `key_vault_id` is required when `enable_disk_encryption_set = true` |
| `validate_ssh_key` | `admin_ssh_key` is required when `disable_password_authentication = true` on Linux |

---

## BMW Sandbox Notes

- **Custom NSG rules are blocked** by BMW Azure Policy (`RequestDisallowedByPolicy`). Always set `nsg_inbound_rules = []` in sandbox environments. Use `use_existing_security_group = true` with a platform-managed NSG for production.
- The default `linux_version` uses a BMW internal marketplace image (`BMW_IAAS_Compute`). Use the Canonical image for non-BMW environments.
- Naming and tagging follow BMW Cloud Commons conventions via the `module.common` dependency.

---

## Testing

```bash
# Plan only (no Azure credentials needed)
terraform test -filter=run.linux_vm_basic

# Full test suite
terraform test
```

See `tftest.hcl` for full test definitions covering Linux VM, Windows VM, data disks, snapshots, and precondition guards.
