- name: Terraform Import All CCG Resources
  run: |
    SUB="4cda8977-68ea-4ca5-aa6a-fae45e7e98f3"
    RG="FSAM-CLEANCONFIG-RG"
    terraform import 'azurerm_resource_group.application_rg' \
      "/subscriptions/$SUB/resourceGroups/$RG"
    terraform import 'module.application_vms[...]...' \
      "/subscriptions/$SUB/.../fs-ccg-app1"
