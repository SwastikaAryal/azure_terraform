resource "azurerm_resource_group" "example" {
  name     = var.resource_group_name
  location = var.resource_group_location
}

resource "azurerm_storage_account" "example" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.example.name
  location                 = azurerm_resource_group.example.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
}

resource "azurerm_storage_share" "example" {
  name                 = var.storage_share_name
  storage_account_name = azurerm_storage_account.example.name
  quota                = var.storage_share_quota
}

resource "azurerm_storage_share_file" "example" {
  name             = var.storage_share_file_name
  storage_share_id = azurerm_storage_share.example.id
  source           = var.storage_share_file_source
}
