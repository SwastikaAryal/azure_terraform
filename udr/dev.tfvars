resource_group_name            = "example-resources"
location                       = "Central US"
route_table_name               = "example-route-table"
disable_bgp_route_propagation  = false
route1_address_prefix          = "10.1.0.0/16"
route1_next_hop_type           = "VnetLocal"

tags = {
  environment = "Production"
}
