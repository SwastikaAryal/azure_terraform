###############################################################################
# tests/monitoring.tftest.hcl
#
# Native Terraform test for Monitoring module
#
# Validates:
#   - Log Analytics Workspace auto-creation
#   - Workspace reuse when ID provided
#   - Action Group configuration via outputs
#   - Diagnostic Settings
#   - Output values after apply
#
# Run:
#   terraform test -filter=tests/monitoring.tftest.hcl
###############################################################################

variables {
  location                     = "eastus"
  resource_group_name          = "DefaultResourceGroup-EUS"
  log_analytics_workspace_name = "law-minitrue-test-9348"
  action_group_name            = "ag-minitrue-test-9348"
  environment                  = "test"
}

###############################################################################
# Run 1 – Workspace auto-created when no ID supplied
###############################################################################
run "log_analytics_workspace_created" {
  command = plan

  variables {
    log_analytics_workspace_id = ""
  }

  assert {
    condition     = length(azurerm_log_analytics_workspace.backup) == 1
    error_message = "A Log Analytics Workspace must be created when log_analytics_workspace_id is empty"
  }

  assert {
    condition     = azurerm_log_analytics_workspace.backup[0].name == var.log_analytics_workspace_name
    error_message = "Workspace name must match variable"
  }

  assert {
    condition     = azurerm_log_analytics_workspace.backup[0].sku == "PerGB2018"
    error_message = "Workspace SKU must be PerGB2018"
  }

  assert {
    condition     = azurerm_log_analytics_workspace.backup[0].retention_in_days == 90
    error_message = "Workspace retention must be 90 days"
  }
}

###############################################################################
# Run 2 – Workspace is NOT created when ID supplied
###############################################################################
run "log_analytics_workspace_reused" {
  command = plan

  variables {
    log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/existing-law"
  }

  assert {
    condition     = length(azurerm_log_analytics_workspace.backup) == 0
    error_message = "Workspace must NOT be created when an existing ID is provided"
  }
}

###############################################################################
# Run 3 – Action Group validation (using outputs)
###############################################################################
run "action_group_validation" {
  command = apply

  assert {
    condition     = output.action_group_id != ""
    error_message = "An Action Group must be created"
  }

  assert {
    condition     = can(regex("Microsoft.Insights/actionGroups", output.action_group_id))
    error_message = "Action Group ID must contain Microsoft.Insights/actionGroups"
  }
}

###############################################################################
# Run 4 – Diagnostic Settings validation
###############################################################################
run "diagnostic_settings_validation" {
  command = plan

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.backup) >= 1
    error_message = "Diagnostic settings must be configured"
  }
}

###############################################################################
# Final Run – Apply validation for computed outputs
###############################################################################
run "monitoring_apply_validation" {
  command = apply

  assert {
    condition     = output.log_analytics_workspace_id != ""
    error_message = "log_analytics_workspace_id output must not be empty"
  }

  assert {
    condition     = output.action_group_id != ""
    error_message = "action_group_id output must not be empty"
  }

  assert {
    condition     = can(regex("Microsoft.OperationalInsights/workspaces", output.log_analytics_workspace_id))
    error_message = "Workspace ID must contain Microsoft.OperationalInsights/workspaces"
  }

  assert {
    condition     = can(regex("Microsoft.Insights/actionGroups", output.action_group_id))
    error_message = "Action Group ID must contain Microsoft.Insights/actionGroups"
  }
}
