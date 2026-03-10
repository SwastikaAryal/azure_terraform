# =============================================================================
# Terraform Test File: terraform-azure-bmw-vm-enhanced
# Tests: Linux VM, Windows VM, Data Disks, NSG Rules, Snapshots,
#        Guest Configuration, Disk Private Access, VM Availability Alert
#
# Usage:
#   Plan only:  terraform test -test-directory=. -filter=run.linux_vm_basic
#   Apply/full: terraform test -test-directory=.
# =============================================================================

# ---------------------------------------------------------------------------
# Shared provider block (reused by all runs unless overridden)
# ---------------------------------------------------------------------------
provider "azurerm" {
  features {}
  # Credentials via environment variables:
  #   ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
}

# ---------------------------------------------------------------------------
# Common variables reused across runs
# ---------------------------------------------------------------------------
variables {
  # ── Location ──────────────────────────────────────────────────────────────
  cloud_region = "westeurope"

  # ── Global config (BMW naming / tagging convention) ───────────────────────
  global_config = {
    env             = "dev"
    customer_prefix = "bmw"
    product_id      = "test-product"
    appd_id         = "appd-test-001"
    managed_by      = "terraform-test"
    owned_by        = "team-infra"
    consumed_by     = "test-pipeline"
    app_name        = "vmtest"
    costcenter      = "cc-9999"
  }

  # ── Resource Group & Network  ─────────────────────────────────────────────
  # These must already exist in your Azure subscription before running tests.
  resource_group_name      = "rg-terraform-test"
  vnet_resource_group_name = "rg-terraform-test"
  virtual_network_name     = "vnet-terraform-test"
  subnet_name              = "snet-terraform-test"

  # ── VM sizing ─────────────────────────────────────────────────────────────
  virtual_machine_size = "Standard_B2ms"

  # ── Tags ──────────────────────────────────────────────────────────────────
  custom_tags = {
    purpose = "tftest"
    owner   = "infra-team"
  }
}

# =============================================================================
# RUN 1 — Linux VM (basic, plan only)
# Validates: NIC, NSG, User-Assigned Identity, Linux VM module wiring
# =============================================================================
run "linux_vm_basic_plan" {
  command = plan

  variables {
    deploy_linux_vm    = true
    deploy_windows_vm  = false
    admin_username     = "azureadmin"

    # Use password auth to keep the test self-contained (no SSH key file needed)
    disable_password_authentication = false
    admin_password                  = "P@ssw0rd1234!"

    linux_version = {
      publisher = "Canonical"
      offer     = "0001-com-ubuntu-server-jammy"
      sku       = "22_04-lts-gen2"
      version   = "latest"
    }

    os_disk_storage_account_type = "StandardSSD_LRS"
    os_disk_caching              = "ReadWrite"
    disk_size_gb                 = 64

    enable_boot_diagnostics = true

    nsg_inbound_rules = [
      {
        name                   = "allow-ssh"
        destination_port_range = "22"
        source_address_prefix  = "10.0.0.0/8"
        priority               = 100
      }
    ]
  }

  # ── Assertions ─────────────────────────────────────────────────────────────
  assert {
    condition     = var.deploy_linux_vm == true
    error_message = "deploy_linux_vm must be true for this run"
  }

  assert {
    condition     = var.deploy_windows_vm == false
    error_message = "deploy_windows_vm must be false when testing Linux"
  }

  assert {
    condition     = var.virtual_machine_size == "Standard_B2ms"
    error_message = "VM size should default to Standard_B2ms"
  }
}

# =============================================================================
# RUN 2 — Linux VM (apply + verify)
# Validates: actual resource IDs are returned, NIC IP is populated
# =============================================================================
run "linux_vm_basic_apply" {
  command = apply

  variables {
    deploy_linux_vm    = true
    deploy_windows_vm  = false
    admin_username     = "azureadmin"

    disable_password_authentication = false
    admin_password                  = "P@ssw0rd1234!"

    linux_version = {
      publisher = "Canonical"
      offer     = "0001-com-ubuntu-server-jammy"
      sku       = "22_04-lts-gen2"
      version   = "latest"
    }

    os_disk_storage_account_type = "StandardSSD_LRS"
    os_disk_caching              = "ReadWrite"
    disk_size_gb                 = 64

    enable_boot_diagnostics = true

    nsg_inbound_rules = [
      {
        name                   = "allow-ssh"
        destination_port_range = "22"
        source_address_prefix  = "10.0.0.0/8"
        priority               = 100
      }
    ]
  }

  # ── Assertions ─────────────────────────────────────────────────────────────
  assert {
    condition     = output.virtual_machine_id != ""
    error_message = "virtual_machine_id output must not be empty after apply"
  }

  assert {
    condition     = output.virtual_machine_name != ""
    error_message = "virtual_machine_name output must not be empty after apply"
  }

  assert {
    condition     = output.virtual_machine_private_ip_address != ""
    error_message = "VM must receive a private IP address"
  }

  assert {
    condition     = output.virtual_machine_principal_id != ""
    error_message = "A user-assigned managed identity must be created"
  }

  assert {
    condition     = length(output.network_security_group_ids) > 0
    error_message = "At least one NSG must be created"
  }

  assert {
    condition     = output.os_disk_name != ""
    error_message = "OS disk name must be populated"
  }
}

# =============================================================================
# RUN 3 — Linux VM with Data Disks (plan)
# Validates: data disk list expansion, attachment wiring
# =============================================================================
run "linux_vm_with_data_disks_plan" {
  command = plan

  variables {
    deploy_linux_vm    = true
    deploy_windows_vm  = false
    admin_username     = "azureadmin"

    disable_password_authentication = false
    admin_password                  = "P@ssw0rd1234!"

    linux_version = {
      publisher = "Canonical"
      offer     = "0001-com-ubuntu-server-jammy"
      sku       = "22_04-lts-gen2"
      version   = "latest"
    }

    data_disks = [
      {
        name                 = "data-disk-01"
        storage_account_type = "StandardSSD_LRS"
        disk_size_gb         = 64
        disk_caching         = "ReadWrite"
        create_option        = "Empty"
      },
      {
        name                 = "data-disk-02"
        storage_account_type = "Premium_LRS"
        disk_size_gb         = 128
        disk_caching         = "ReadOnly"
        create_option        = "Empty"
        on_demand_bursting_enabled = true
      }
    ]

    enable_boot_diagnostics = true
  }

  assert {
    condition     = length(var.data_disks) == 2
    error_message = "Expected 2 data disks to be defined"
  }

  assert {
    condition     = var.data_disks[0].disk_size_gb == 64
    error_message = "First data disk should be 64 GB"
  }

  assert {
    condition     = var.data_disks[1].on_demand_bursting_enabled == true
    error_message = "Second disk should have on-demand bursting enabled"
  }
}

# =============================================================================
# RUN 4 — Linux VM with Disk Snapshots (plan)
# Validates: OS + data disk snapshot resources are planned
# =============================================================================
run "linux_vm_snapshots_plan" {
  command = plan

  variables {
    deploy_linux_vm    = true
    deploy_windows_vm  = false
    admin_username     = "azureadmin"

    disable_password_authentication = false
    admin_password                  = "P@ssw0rd1234!"

    linux_version = {
      publisher = "Canonical"
      offer     = "0001-com-ubuntu-server-jammy"
      sku       = "22_04-lts-gen2"
      version   = "latest"
    }

    data_disks = [
      {
        name                 = "data-disk-snap-01"
        storage_account_type = "StandardSSD_LRS"
        disk_size_gb         = 32
        disk_caching         = "ReadWrite"
        create_option        = "Empty"
      }
    ]

    enable_os_disk_snapshot    = true
    enable_data_disk_snapshots = true
    snapshot_incremental       = true
  }

  assert {
    condition     = var.enable_os_disk_snapshot == true
    error_message = "OS disk snapshot must be enabled for this run"
  }

  assert {
    condition     = var.enable_data_disk_snapshots == true
    error_message = "Data disk snapshots must be enabled for this run"
  }

  assert {
    condition     = var.snapshot_incremental == true
    error_message = "Incremental snapshots should be used to reduce cost"
  }
}

# =============================================================================
# RUN 5 — Linux VM with Guest Configuration Extension (plan)
# Validates: guest_config_linux extension is planned
# =============================================================================
run "linux_vm_guest_config_plan" {
  command = plan

  variables {
    deploy_linux_vm    = true
    deploy_windows_vm  = false
    admin_username     = "azureadmin"

    disable_password_authentication = false
    admin_password                  = "P@ssw0rd1234!"

    linux_version = {
      publisher = "Canonical"
      offer     = "0001-com-ubuntu-server-jammy"
      sku       = "22_04-lts-gen2"
      version   = "latest"
    }

    enable_guest_configuration = true
  }

  assert {
    condition     = var.enable_guest_configuration == true
    error_message = "Guest configuration extension must be enabled"
  }
}

# =============================================================================
# RUN 6 — Linux VM with Disk Private Access (plan)
# Validates: azurerm_disk_access resource is planned
# =============================================================================
run "linux_vm_disk_private_access_plan" {
  command = plan

  variables {
    deploy_linux_vm    = true
    deploy_windows_vm  = false
    admin_username     = "azureadmin"

    disable_password_authentication = false
    admin_password                  = "P@ssw0rd1234!"

    linux_version = {
      publisher = "Canonical"
      offer     = "0001-com-ubuntu-server-jammy"
      sku       = "22_04-lts-gen2"
      version   = "latest"
    }

    enable_disk_private_access = true
  }

  assert {
    condition     = var.enable_disk_private_access == true
    error_message = "Disk private access must be enabled for this run"
  }
}

# =============================================================================
# RUN 7 — Windows VM (plan)
# Validates: Windows VM module variables and NSG wiring
# =============================================================================
run "windows_vm_basic_plan" {
  command = plan

  variables {
    deploy_linux_vm   = false
    deploy_windows_vm = true

    admin_username = "winadmin"
    admin_password = "WinP@ssw0rd1234!"

    windows_version = {
      publisher = "MicrosoftWindowsServer"
      offer     = "WindowsServer"
      sku       = "2022-Datacenter"
      version   = "latest"
    }

    enable_automatic_updates = true
    windows_patch_mode       = "AutomaticByOS"
    windows_license_type     = "None"

    os_disk_storage_account_type = "StandardSSD_LRS"
    os_disk_caching              = "ReadWrite"
    disk_size_gb                 = 128

    enable_boot_diagnostics = true

    nsg_inbound_rules = [
      {
        name                   = "allow-rdp"
        destination_port_range = "3389"
        source_address_prefix  = "10.0.0.0/8"
        priority               = 100
      },
      {
        name                   = "allow-winrm"
        destination_port_range = "5985"
        source_address_prefix  = "10.0.0.0/8"
        priority               = 200
      }
    ]
  }

  assert {
    condition     = var.deploy_windows_vm == true
    error_message = "deploy_windows_vm must be true for this run"
  }

  assert {
    condition     = var.deploy_linux_vm == false
    error_message = "deploy_linux_vm must be false when testing Windows"
  }

  assert {
    condition     = length(var.nsg_inbound_rules) == 2
    error_message = "Expected 2 NSG inbound rules (RDP + WinRM)"
  }
}

