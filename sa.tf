resource "azurerm_storage_management_policy" "this" {
  storage_account_id = var.storage_management_policy.storage_account_id

  dynamic "rule" {
    for_each = var.storage_management_policy.rules

    content {
      name    = rule.value.name
      enabled = rule.value.enabled

      filters {
        prefix_match = rule.value.filters.prefix_match
        blob_types   = rule.value.filters.blob_types

        dynamic "match_blob_index_tag" {
          for_each = rule.value.filters.match_blob_index_tag != null ? [rule.value.filters.match_blob_index_tag] : []

          content {
            name      = match_blob_index_tag.value.name
            operation = match_blob_index_tag.value.operation
            value     = match_blob_index_tag.value.value
          }
        }
      }

      actions {

        base_blob {
          tier_to_cool_after_days_since_modification_greater_than    = rule.value.actions.base_blob.tier_to_cool_after_days_since_modification_greater_than
          tier_to_archive_after_days_since_modification_greater_than = rule.value.actions.base_blob.tier_to_archive_after_days_since_modification_greater_than
          delete_after_days_since_modification_greater_than          = rule.value.actions.base_blob.delete_after_days_since_modification_greater_than
        }

        dynamic "snapshot" {
          for_each = rule.value.actions.snapshot != null ? [rule.value.actions.snapshot] : []

          content {
            delete_after_days_since_creation_greater_than = lookup(snapshot.value, "delete_after_days_since_creation_greater_than", null)
            change_tier_to_archive_after_days_since_creation = lookup(snapshot.value, "change_tier_to_archive_after_days_since_creation", null)
            change_tier_to_cool_after_days_since_creation    = lookup(snapshot.value, "change_tier_to_cool_after_days_since_creation", null)
          }
        }

        dynamic "version" {
          for_each = rule.value.actions.version != null ? [rule.value.actions.version] : []

          content {
            change_tier_to_archive_after_days_since_creation = version.value.change_tier_to_archive_after_days_since_creation
            change_tier_to_cool_after_days_since_creation    = version.value.change_tier_to_cool_after_days_since_creation
            delete_after_days_since_creation                 = version.value.delete_after_days_since_creation
          }
        }
      }
    }
  }
}

##########variable block
variable "storage_management_policy" {
  description = "Configuration for Azure Storage Management Policy"
  type = object({
    storage_account_id = string
    rules = list(object({
      name    = string
      enabled = bool

      filters = object({
        prefix_match = list(string)
        blob_types   = list(string)
        match_blob_index_tag = optional(object({
          name      = string
          operation = string
          value     = string
        }))
      })

      actions = object({
        base_blob = object({
          tier_to_cool_after_days_since_modification_greater_than    = number
          tier_to_archive_after_days_since_modification_greater_than = number
          delete_after_days_since_modification_greater_than          = number
        })

        snapshot = optional(object({
          delete_after_days_since_creation_greater_than = number
          change_tier_to_archive_after_days_since_creation = optional(number)
          change_tier_to_cool_after_days_since_creation    = optional(number)
        }))

        version = optional(object({
          change_tier_to_archive_after_days_since_creation = number
          change_tier_to_cool_after_days_since_creation    = number
          delete_after_days_since_creation                 = number
        }))
      })
    }))
  })
}

#tfvars block
storage_management_policy = {
  storage_account_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Storage/storageAccounts/examplestorage"

  rules = [
    {
      name    = "rule1"
      enabled = true

      filters = {
        prefix_match = ["container1/prefix1"]
        blob_types   = ["blockBlob"]
        match_blob_index_tag = {
          name      = "tag1"
          operation = "=="
          value     = "val1"
        }
      }

      actions = {
        base_blob = {
          tier_to_cool_after_days_since_modification_greater_than    = 10
          tier_to_archive_after_days_since_modification_greater_than = 50
          delete_after_days_since_modification_greater_than          = 100
        }

        snapshot = {
          delete_after_days_since_creation_greater_than = 30
        }
      }
    },
    {
      name    = "rule2"
      enabled = false

      filters = {
        prefix_match = ["container2/prefix1", "container2/prefix2"]
        blob_types   = ["blockBlob"]
      }

      actions = {
        base_blob = {
          tier_to_cool_after_days_since_modification_greater_than    = 11
          tier_to_archive_after_days_since_modification_greater_than = 51
          delete_after_days_since_modification_greater_than          = 101
        }

        snapshot = {
          change_tier_to_archive_after_days_since_creation = 90
          change_tier_to_cool_after_days_since_creation    = 23
          delete_after_days_since_creation_greater_than    = 31
        }

        version = {
          change_tier_to_archive_after_days_since_creation = 9
          change_tier_to_cool_after_days_since_creation    = 90
          delete_after_days_since_creation                 = 3
        }
      }
    }
  ]
}

#output.tf
output "storage_management_policy_id" {
  description = "ID of the Storage Management Policy"
  value       = azurerm_storage_management_policy.example.id
}


