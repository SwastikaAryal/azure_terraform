resource_group_name             = "rg-clng-dev-ceaz-cus-002"
location                        = "Central US"
vm_name                         = "CNDWCLNGCUS001"
username                        = "windows"
password                        = "123$AVG7YU"
subnet                          = "/subscriptions/9a84aa6f-97f5-4fb2-96c7-f42602d7ae80/resourceGroups/rg-clng-dev-ceaz-cus-001/providers/Microsoft.Network/virtualNetworks/vnet-clng-dev-ceaz-cus-001/subnets/snet-clng-dev-ceaz-cus-007"
vnet                            = "/subscriptions/9a84aa6f-97f5-4fb2-96c7-f42602d7ae80/resourceGroups/rg-clng-dev-ceaz-cus-001/providers/Microsoft.Network/virtualNetworks/vnet-clng-dev-ceaz-cus-001"
vmnetwork                       = "centene_windows_vmnetwork"
nic_name                        = "vmnetwork"
storage_account_type            = "Standard_LRS"
ip_config_name                  = "internal"
private_ip_address_allocation   = "Dynamic"
size                            = "Standard_D2s_v3"
source_image_id                 = "/subscriptions/9a84aa6f-97f5-4fb2-96c7-f42602d7ae80/resourceGroups/rg-clng-dev-ceaz-cus-002/providers/Microsoft.Compute/galleries/sigclngdevceazcus01/images/Windows10EnterpriseGen2/versions/latest"
caching                         = "ReadWrite"