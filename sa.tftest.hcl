# =================================================================================================
# File: terraform/modules/v2/storage_account/tests/storage_account.tftest.hcl
# Run:  terraform test -chdir=terraform/modules/v2/storage_account
# =================================================================================================

# ---------------------------------------------------------------------------
# Mock provider – all azurerm resources/data sources return synthetic values
# ---------------------------------------------------------------------------
mock_provider "azurerm" {}

# ---------------------------------------------------------------------------
# Shared variable values reused across every run block
# ---------------------------------------------------------------------------
variables {
  global_config = {
    env             = "dev"
    customer_prefix = "cgbp"
    product_id      = "SWP-0815"
    appd_id         = "APPD-304118"
    app_name        = "sto10weu"
    costcenter      = "0815"
  }

  cloud_region        = "eastus"
  resource_group_name = "rg-test"

  private_link_endpoint_subnet = {
    name                 = "snet-pe"
    resource_group_name  = "rg-network"
    virtual_network_name = "vnet-spoke"
  }

  create_private_endpoint = true
  custom_name_suffix      = "data"
  tags                    = { Environment = "Test" }
}

# ==========================================================================
# TEST 1 – Defender for Storage is created when enabled
# ==========================================================================
run "defender_for_storage_enabled" {
  command = plan

  variables {
    enable_defender_for_storage = true
  }

  assert {
    condition     = length(azurerm_security_center_subscription_pricing.main) == 1
    error_message = "Defender for Storage resource must be created when enabled."
  }

  assert {
    condition     = azurerm_security_center_subscription_pricing.main[0].tier == "Standard"
    error_message = "Defender tier must be Standard."
  }

  assert {
    condition     = azurerm_security_center_subscription_pricing.main[0].resource_type == "StorageAccounts"
    error_message = "Defender resource_type must be StorageAccounts."
  }
}

# ==========================================================================
# TEST 2 – Defender for Storage is skipped when disabled
# ==========================================================================
run "defender_for_storage_disabled" {
  command = plan

  variables {
    enable_defender_for_storage = false
  }

  assert {
    condition     = length(azurerm_security_center_subscription_pricing.main) == 0
    error_message = "Defender for Storage must not be created when disabled."
  }
}

# ==========================================================================
# TEST 3 – Storage management policy creates rules
# ==========================================================================
run "management_policy_with_rules" {
  command = plan

  variables {
    enable_defender_for_storage = false

    storage_management_policy = {
      rules = [
        {
          name    = "move-to-cool-tier"
          enabled = true
          filters = {
            prefix_match = ["container1/logs"]
            blob_types   = ["blockBlob"]
          }
          actions = {
            base_blob = {
              tier_to_cool_after_days_since_modification_greater_than    = 30
              tier_to_archive_after_days_since_modification_greater_than = 90
              delete_after_days_since_modification_greater_than          = 365
            }
          }
        }
      ]
    }
  }

  assert {
    condition     = length(azurerm_storage_management_policy.this) == 1
    error_message = "Storage management policy must be created when rules are provided."
  }
}

# ==========================================================================
# TEST 4 – Storage management policy skipped with empty rules
# ==========================================================================
run "management_policy_no_rules" {
  command = plan

  variables {
    enable_defender_for_storage = false
    storage_management_policy   = { rules = [] }
  }

  assert {
    condition     = length(azurerm_storage_management_policy.this) == 0
    error_message = "Storage management policy must not be created when rules list is empty."
  }
}

# ==========================================================================
# TEST 5 – Monitoring resources are created when enabled
# ==========================================================================
run "monitoring_enabled" {
  command = plan

  variables {
    enable_defender_for_storage = false

    monitoring = {
      enabled = true
      action_group = {
        name       = "ag-storage-alerts"
        short_name = "stg-alert"
        email_receivers = [
          {
            name                    = "ops-team"
            email_address           = "ops@company.com"
            use_common_alert_schema = true
          }
        ]
      }
      metric_alert = {
        name   = "alert-storage-availability"
        scopes = []
        criteria = {
          metric_namespace = "Microsoft.Storage/storageAccounts"
          metric_name      = "Availability"
          aggregation      = "Average"
          operator         = "LessThan"
          threshold        = 99.9
        }
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_action_group.this) == 1
    error_message = "Action group must be created when monitoring is enabled."
  }

  assert {
    condition     = azurerm_monitor_action_group.this[0].name == "ag-storage-alerts"
    error_message = "Action group name must match input."
  }

  assert {
    condition     = azurerm_monitor_action_group.this[0].short_name == "stg-alert"
    error_message = "Action group short_name must match input."
  }

  assert {
    condition     = length(azurerm_monitor_metric_alert.this) == 1
    error_message = "Metric alert must be created when monitoring is enabled."
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this[0].name == "alert-storage-availability"
    error_message = "Metric alert name must match input."
  }
}

# ==========================================================================
# TEST 6 – Monitoring resources are skipped when disabled
# ==========================================================================
run "monitoring_disabled" {
  command = plan

  variables {
    enable_defender_for_storage = false
    monitoring                  = null
  }

  assert {
    condition     = length(azurerm_monitor_action_group.this) == 0
    error_message = "Action group must not be created when monitoring is null."
  }

  assert {
    condition     = length(azurerm_monitor_metric_alert.this) == 0
    error_message = "Metric alert must not be created when monitoring is null."
  }
}
