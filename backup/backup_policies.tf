# App VMs – selective disk backup (exclude OS temp disk, LUN 1 = ephemeral)
resource "azurerm_backup_protected_vm" "app_vms_selective" {
  for_each = { for idx, id in var.app_vm_ids : tostring(idx) => id }

  resource_group_name = local.resource_group_name
  recovery_vault_name = azurerm_recovery_services_vault.main.name
  source_vm_id        = each.value
  backup_policy_id    = azurerm_backup_policy_vm.standard.id

  # Exclude the temporary/resource disk (LUN 1 for most Azure VM sizes)
  # Include only OS disk (no LUN = OS disk) and all attached data disks except LUN 1
  include_disk_luns = null  # null = include all; set specific LUNs to include
  exclude_disk_luns = [1]   # LUN 1 = temp/cache disk – excluded from backup

  lifecycle {
    # If app_vm_ids changes, existing protected items need to be managed carefully
    ignore_changes = [source_vm_id]
  }
}
