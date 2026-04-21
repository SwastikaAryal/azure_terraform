# =================================================================================================
# File: terraform/modules/v2/storage_account/tests/storage_account.tftest.hcl
# Run:  terraform test -chdir=terraform/modules/v2/storage_account
# Note: This runs a real apply against Azure. Resources are auto-destroyed after tests.
#       Make sure terraform.tfvars has real values (no XXXXXXXX placeholders) before running.
# =================================================================================================

# ==========================================================================
# TEST 1 – Full storage account apply with Defender enabled
# ==========================================================================
run "storage_account_apply" {
  command = apply

  assert {
    condition     = length(azurerm_security_center_subscription_pricing.main) == 1
    error_message = "Defender for Storage must be created."
  }

  assert {
    condition     = azurerm_security_center_subscription_pricing.main[0].tier == "Standard"
    error_message = "Defender tier must be Standard."
  }

  assert {
    condition     = azurerm_security_center_subscription_pricing.main[0].resource_type == "StorageAccounts"
    error_message = "Defender resource_type must be StorageAccounts."
  }

  assert {
    condition     = length(azurerm_storage_management_policy.this) == 1
    error_message = "Storage management policy must be created."
  }

  assert {
    condition     = length(azurerm_monitor_action_group.this) == 1
    error_message = "Monitor action group must be created."
  }

  assert {
    condition     = azurerm_monitor_action_group.this[0].name == "ag-storage-alerts-prod"
    error_message = "Action group name must match terraform.tfvars value."
  }

  assert {
    condition     = length(azurerm_monitor_metric_alert.this) == 1
    error_message = "Monitor metric alert must be created."
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this[0].name == "alert-storage-availability"
    error_message = "Metric alert name must match terraform.tfvars value."
  }
}
