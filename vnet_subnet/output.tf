output "virtual_network_id" {
  description = "ID of the created virtual network"
  value       = azurerm_virtual_network.example.id
}

output "subnet1_id" {
  description = "ID of subnet1"
  value       = azurerm_virtual_network.example.subnet["subnet1"].id
}

output "subnet2_id" {
  description = "ID of subnet2"
  value       = azurerm_virtual_network.example.subnet["subnet2"].id
}
