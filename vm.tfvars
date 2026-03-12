# =============================================================================
# Global Variables
# =============================================================================
cloud_region = "eastus"

global_config = {
  env             = "dev"
  customer_prefix = "acme"
  product_id      = "prod01"
  appd_id         = "app01"
  managed_by      = "infra-team"
  owned_by        = "dev-team"
  consumed_by     = "internal"
  app_name        = "demo-vm"
  costcenter      = "CC1001"
}

cost_tag_1   = "ProjectX"
cost_tag_2   = "TeamA"
custom_tags  = { "department" = "IT", "priority" = "high" }
custom_name  = "demo-vm-custom"
commons_file_json      = "commons.json"
local_file_json_tpl    = "local.json.tpl"
naming_file_json_tpl   = "naming.json.tpl"

# =============================================================================
# VM Type Selection
# =============================================================================
deploy_windows_vm = true
deploy_linux_vm   = false

# =============================================================================
# Resource Group & Network
# =============================================================================
resource_group_name       = "rg-demo-vm"
vnet_resource_group_name  = "rg-demo-network"
virtual_network_name      = "vnet-demo"
subnet_name               = "subnet-demo"
ip_forwarding_enabled     = false
accelerated_networking_enabled = true
private_ip_address_allocation_type = "Dynamic"
private_ip_address        = null

# =============================================================================
# Identity & Encryption
# =============================================================================
use_own_key_for_disk_encryption  = false
create_user_assigned_identity    = true
uai_principal_name               = "demo-uai"
uai_principal_rg_name            = "rg-demo-uai"
disk_encryption_key_id           = null
enable_disk_encryption_set       = false
auto_key_rotation_enabled        = false
key_vault_id                     = null
enable_encryption_at_host        = false
managed_identity_type            = "UserAssigned"

# =============================================================================
# Monitoring & Logging
# =============================================================================
enable_log_analytics_integration = true
enable_boot_diagnostics          = true
log_analytics_id                 = "/subscriptions/xxxx/resourceGroups/rg-demo/providers/Microsoft.OperationalInsights/workspaces/log-analytics-demo"
log_analytics_name               = "log-analytics-demo"

# =============================================================================
# VM Configuration
# =============================================================================
network_interface_ids = ["/subscriptions/.../nic/demo-nic"]
admin_username        = "azureadmin"
admin_password        = "P@ssw0rd123!"
virtual_machine_size  = "Standard_B2ms"
custom_data           = null
allow_extension_operations = true
source_image_id       = null
availability_zone     = null
enable_ultra_ssd_data_disk_storage_support = false
computer_name         = "demo-vm"
random_password_length = 32
storage_account_uri    = null

# =============================================================================
# Windows-Specific
# =============================================================================
windows_version = {
  publisher = "MicrosoftWindowsServer"
  offer     = "WindowsServer"
  sku       = "2022-Datacenter"
  version   = "latest"
}
enable_automatic_updates  = true
windows_patch_mode        = "AutomaticByOS"
windows_license_type      = "None"
winrm_protocol            = "https"

# =============================================================================
# Linux-Specific
# =============================================================================
linux_version = {
  publisher = "Canonical"
  offer     = "UbuntuServer"
  sku       = "22_04-lts-gen2"
  version   = "latest"
}
linux_patch_mode              = "ImageDefault"
disable_password_authentication = true
admin_ssh_key = {
  content   = null
  file_path = "~/.ssh/id_rsa.pub"
}

# =============================================================================
# OS Disk
# =============================================================================
os_disk_name                  = "demo-vm-osdisk"
os_disk_storage_account_type  = "StandardSSD_LRS"
os_disk_caching               = "ReadWrite"
disk_size_gb                  = 127
enable_os_disk_write_accelerator = false

# =============================================================================
# Data Disks
# =============================================================================
data_disks = [
  {
    name                       = "datadisk1"
    storage_account_type        = "StandardSSD_LRS"
    disk_size_gb               = 128
    disk_caching               = "ReadWrite"
    create_option              = "Empty"
    on_demand_bursting_enabled = false
    performance_tier           = "Standard"
    network_access_policy      = "AllowAll"
    public_network_access_enabled = true
    trusted_launch_enabled     = false
  }
]

# =============================================================================
# NSG
# =============================================================================
use_existing_security_group   = false
existing_network_security_group_id = null
existing_nsg_name             = null
nsg_inbound_rules = [
  {
    name                   = "rdp"
    destination_port_range = "3389"
    source_address_prefix  = "*"
    priority               = 100
    direction              = "Inbound"
    access                 = "Allow"
    protocol               = "Tcp"
  }
]

# =============================================================================
# Recovery Services Vault
# =============================================================================
enable_recovery_service_vault     = true
backup_vault_use_managed_identity = false
backup_vault_identity_ids         = []
encrypt_vault                     = false
vault_sku                          = "Standard"
vault_public_network_access_enabled = false
vault_immutability                = null
vault_storage_mode_type           = "GeoRedundant"
vault_cross_region_restore_enabled = false
vault_soft_delete_enabled          = true
vault_vms = {
  "demo-vm" = {
    vm_id        = "/subscriptions/.../resourceGroups/rg-demo-vm/providers/Microsoft.Compute/virtualMachines/demo-vm"
    include_disk_luns = [0]
    backup = {
      frequency = "Daily"
      time      = "22:00"
    }
  }
}

# =============================================================================
# Snapshots & Extensions
# =============================================================================
enable_os_disk_snapshot          = false
enable_data_disk_snapshots       = false
snapshot_incremental             = true
enable_asr_extension             = false
enable_guest_configuration       = false
enable_disk_private_access       = false

secure_boot_enabled               = false
vtpm_enabled                      = false
secure_vm_disk_encryption_set_id  = null

availability_set_id                = null
proximity_placement_group_id       = null
dedicated_host_id                  = null
dedicated_host_group_id            = null
capacity_reservation_group_id      = null

reboot_setting                      = "IfRequired"
vm_agent_platform_updates_enabled   = true
enable_termination_notification     = false
termination_notification_timeout    = "PT5M"
enable_hibernation                  = false

gallery_applications = []

plan = null
enable_os_image_notification = false
os_image_notification_timeout = "PT15M"

priority        = "Regular"
max_price       = -1
eviction_policy = "Deallocate"

enable_vm_availability_alert = false
vm_alert_action_group_ids    = []
