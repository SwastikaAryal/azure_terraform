data "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                  = var.workspace_name
 resource_group_name    = var.resource_group_name
}

resource "azurerm_log_analytics_solution" "log_analytics_solution" {
  solution_name         = var.solution_name
  location              = var.location
  resource_group_name   = var.resource_group_name
  workspace_resource_id = data.azurerm_log_analytics_workspace.log_analytics_workspace.id
  workspace_name        = var.workspace_name

  plan {
    publisher = var.publisher
    product   = var.product
  }
}