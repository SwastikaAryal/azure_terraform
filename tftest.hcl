run "create_load_balancer" {

  command = apply

  variables {
    enable_load_balancer          = true
    load_balancer_protocol        = "Tcp"
    load_balancer_frontend_port   = 80
    load_balancer_backend_port    = 80
    health_probe_protocol         = "Http"
    health_probe_port             = 80
    health_probe_path             = "/"

    cloud_region       = "eastus"
    resource_group_name = "test-rg"
  }

  assert {
    condition     = azurerm_public_ip.lb[0].sku == "Standard"
    error_message = "Public IP should be Standard SKU"
  }

  assert {
    condition     = azurerm_lb.main[0].sku == "Standard"
    error_message = "Load Balancer must use Standard SKU"
  }

  assert {
    condition     = azurerm_lb_backend_address_pool.main[0].name == "BackendPool"
    error_message = "Backend pool was not created correctly"
  }

  assert {
    condition     = azurerm_lb_probe.health[0].port == 80
    error_message = "Health probe port should be 80"
  }

  assert {
    condition     = azurerm_lb_rule.main[0].frontend_port == 80
    error_message = "Frontend port should be 80"
  }

}
