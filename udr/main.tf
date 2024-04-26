provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "example" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_route_table" "example" {
  name                          = var.route_table_name
  location                      = azurerm_resource_group.example.location
  resource_group_name           = azurerm_resource_group.example.name
  disable_bgp_route_propagation = var.disable_bgp_route_propagation

  route {
    name           = "route1"
    address_prefix = var.route1_address_prefix
    next_hop_type  = var.route1_next_hop_type
  }

  tags = var.tags
}
