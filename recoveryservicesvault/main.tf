resource "azurerm_recovery_services_vault" "recovery_services_vault" {
  name                = var.rsv_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku

  soft_delete_enabled = var.soft_delete_enabled
}