resource "azurerm_resource_group" "example" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_network_security_group" "example" {
  name                = var.security_group_name
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
}

resource "azurerm_virtual_network" "example" {
  name                = var.virtual_network_name
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  address_space       = var.address_space
  dns_servers         = var.dns_servers

  subnet {
    name           = var.subnet1_name
    address_prefix = var.subnet1_prefix
  }

  subnet {
    name           = var.subnet2_name
    address_prefix = var.subnet2_prefix
    security_group = azurerm_network_security_group.example.id
  }

  tags = var.tags
}
