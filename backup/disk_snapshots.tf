# -----------------------------------------------------------------
# Data Protection Backup Vault
# -----------------------------------------------------------------
resource "azurerm_data_protection_backup_vault" "disk_vault" {
  name                = "dpbv-minitrue-disk-snapshots"
  resource_group_name = local.resource_group_name
  location            = local.location
  datastore_type      = "VaultStore"
  redundancy          = "GeoRedundant"
  tags                = local.tags

  identity {
    type = "SystemAssigned"
  }
}

# -----------------------------------------------------------------
# Role Assignments for Vault
# -----------------------------------------------------------------
resource "azurerm_role_assignment" "disk_vault_snapshot_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${local.resource_group_name}"
  role_definition_name = "Disk Snapshot Contributor"
  principal_id         = azurerm_data_protection_backup_vault.disk_vault.identity[0].principal_id
}

resource "azurerm_role_assignment" "disk_vault_reader" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${local.resource_group_name}"
  role_definition_name = "Disk Backup Reader"
  principal_id         = azurerm_data_protection_backup_vault.disk_vault.identity[0].principal_id
}
resource "azurerm_role_assignment" "disk_vault_snapshot_rg" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${local.resource_group_name}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_data_protection_backup_vault.disk_vault.identity[0].principal_id
}

# -----------------------------------------------------------------
# OS Disk Backup Policy (7-day retention, 4-hour intervals)
# -----------------------------------------------------------------
resource "azurerm_data_protection_backup_policy_disk" "os_disk" {
  name     = "dpbpol-os-disk-7d"
  vault_id = azurerm_data_protection_backup_vault.disk_vault.id

  backup_repeating_time_intervals = ["R/2024-01-01T02:00:00+00:00/PT4H"]
  default_retention_duration      = "P7D"

  retention_rule {
    name     = "Weekly"
    duration = "P4W"
    priority = 25
    criteria {
      absolute_criteria = "FirstOfWeek"
    }
  }
}

# -----------------------------------------------------------------
# Data Disk Backup Policy (7-day retention, daily)
# -----------------------------------------------------------------
resource "azurerm_data_protection_backup_policy_disk" "data_disk" {
  name     = "dpbpol-data-disk-7d"
  vault_id = azurerm_data_protection_backup_vault.disk_vault.id

  backup_repeating_time_intervals = ["R/2024-01-01T23:00:00+00:00/P1D"]
  default_retention_duration      = "P7D"

  retention_rule {
    name     = "Weekly"
    duration = "P4W"
    priority = 25
    criteria {
      absolute_criteria = "FirstOfWeek"
    }
  }
}

# -----------------------------------------------------------------
# Backup Instances for App/Web VM OS & Data Disks
# -----------------------------------------------------------------
resource "azurerm_data_protection_backup_instance_disk" "app_os_disks" {
  for_each = { for idx, id in var.app_vm_os_disk_ids : tostring(idx) => id }

  name                         = "dpbi-app-os-disk-${each.key}"
  location                     = local.location
  vault_id                     = azurerm_data_protection_backup_vault.disk_vault.id
  disk_id                      = each.value
  snapshot_resource_group_name = var.snapshot_resource_group_name
  backup_policy_id             = azurerm_data_protection_backup_policy_disk.os_disk.id
}

resource "azurerm_data_protection_backup_instance_disk" "web_os_disks" {
  for_each = { for idx, id in var.web_vm_os_disk_ids : tostring(idx) => id }

  name                         = "dpbi-web-os-disk-${each.key}"
  location                     = local.location
  vault_id                     = azurerm_data_protection_backup_vault.disk_vault.id
  disk_id                      = each.value
  snapshot_resource_group_name = var.snapshot_resource_group_name
  backup_policy_id             = azurerm_data_protection_backup_policy_disk.os_disk.id
}

resource "azurerm_data_protection_backup_instance_disk" "app_data_disks" {
  for_each = { for idx, id in var.app_vm_data_disk_ids : tostring(idx) => id }

  name                         = "dpbi-app-data-disk-${each.key}"
  location                     = local.location
  vault_id                     = azurerm_data_protection_backup_vault.disk_vault.id
  disk_id                      = each.value
  snapshot_resource_group_name = var.snapshot_resource_group_name
  backup_policy_id             = azurerm_data_protection_backup_policy_disk.data_disk.id
}

resource "azurerm_data_protection_backup_instance_disk" "web_data_disks" {
  for_each = { for idx, id in var.web_vm_data_disk_ids : tostring(idx) => id }

  name                         = "dpbi-web-data-disk-${each.key}"
  location                     = local.location
  vault_id                     = azurerm_data_protection_backup_vault.disk_vault.id
  disk_id                      = each.value
  snapshot_resource_group_name = var.snapshot_resource_group_name
  backup_policy_id             = azurerm_data_protection_backup_policy_disk.data_disk.id
}

# # -----------------------------------------------------------------
# # Cross-Region Snapshot Copy Policy
# # -----------------------------------------------------------------
# resource "azurerm_policy_definition" "cross_region_snapshot_copy" {
#   name         = "pol-copy-snapshots-to-secondary2"
#   policy_type  = "Custom"
#   mode         = "Indexed"
#   display_name = "Copy managed disk snapshots to secondary region"
#   description  = "Ensures snapshots are copied to DR region for BCP"

#   metadata = jsonencode({
#     category = "Backup"
#     version  = "1.0.0"
#   })

#   policy_rule = jsonencode({
#     if = {
#       allOf = [
#         { field = "type", equals = "Microsoft.Compute/snapshots" },
#         { field = "location", equals = var.location },
#         { field = "tags['dr-copy']", notEquals = "true" }
#       ]
#     }
#     then = {
#       effect = "deployIfNotExists"
#       details = {
#         type              = "Microsoft.Compute/snapshots"
#         roleDefinitionIds = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
#         deployment = {
#           properties = {
#             mode       = "incremental"
#             template   = {
#               "$schema"      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
#               contentVersion = "1.0.0.0"
#               parameters = {
#                 snapshotName = { type = "string" }
#                 sourceRG     = { type = "string" }
#                 targetRG     = { type = "string" }
#                 targetLoc    = { type = "string" }
#                 sourceId     = { type = "string" }
#               }
#               resources = [
#                 {
#                   type       = "Microsoft.Compute/snapshots"
#                   apiVersion = "2023-01-02"
#                   name       = "[concat(parameters('snapshotName'),'-dr')]"
#                   location   = "[parameters('targetLoc')]"
#                   tags = {
#                     "dr-copy" = "true"
#                   }
#                   properties = {
#                     creationData = {
#                       createOption     = "CopyStart"
#                       sourceResourceId = "[parameters('sourceId')]"
#                     }
#                   }
#                 }
#               ]
#             }
#             parameters = {
#               snapshotName = { value = "[field('name')]" }
#               sourceRG     = { value = "[resourceGroup().name]" }
#               targetRG     = { value = var.snapshot_resource_group_name }
#               targetLoc    = { value = var.secondary_location }
#               sourceId     = { value = "[field('id')]" }
#             }
#           }
#         }
#       }
#     }
#   })
# }

# resource "azurerm_subscription_policy_assignment" "cross_region_snapshot" {
#   depends_on           = [azurerm_policy_definition.cross_region_snapshot_copy]
#   name                 = "assign-cross-region-snapshot-copy2"
#   subscription_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
#   policy_definition_id = azurerm_policy_definition.cross_region_snapshot_copy.id
#   display_name         = "Cross-Region Snapshot Copy – DR"
#   description          = "Copy snapshots to secondary region for DR"

#   identity {
#     type = "SystemAssigned"
#   }

#   location = local.location
# }

# # -----------------------------------------------------------------
# # Snapshot Cleanup Policy
# # -----------------------------------------------------------------
# resource "azurerm_policy_definition" "snapshot_cleanup" {
#   name         = "pol-cleanup-old-snapshots"
#   policy_type  = "Custom"
#   mode         = "All"
#   display_name = "Delete managed disk snapshots older than 7 days"
#   description  = "Automatically removes snapshots beyond the 7-day retention window"

#   metadata = jsonencode({
#     category = "Backup"
#     version  = "1.0.0"
#   })

#   policy_rule = jsonencode({
#     if = {
#       allOf = [
#         {
#           field = "Microsoft.Compute/snapshots/timeCreated"
#           less  = "[addDays(utcNow(), -7)]"
#         }
#       ]
#     }
#     then = {
#       effect = "audit" # or "deny" if you prefer
#     }
#   })
# }

# resource "azurerm_subscription_policy_assignment" "snapshot_cleanup" {
#   depends_on           = [azurerm_policy_definition.snapshot_cleanup]
#   name                 = "assign-snapshot-cleanup"
#   subscription_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
#   policy_definition_id = azurerm_policy_definition.snapshot_cleanup.id
#   display_name         = "Snapshot Cleanup – 7-day Retention"
#   description          = "Enforce 7-day snapshot retention"

#   identity {
#     type = "SystemAssigned"
#   }

#   location = local.location
# }