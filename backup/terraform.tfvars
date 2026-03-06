###############################################################################
# terraform.tfvars.example
###############################################################################

location            = "eastus"
secondary_location  = "westus"
resource_group_name = "DefaultResourceGroup-EUS"
environment         = "prod"
vault_name          = "rsv-minitrue-backup"

snapshot_resource_group_name = "DefaultResourceGroup-EUS"

# App VM resource IDs
app_vm_ids = [
  # "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Compute/virtualMachines/app-vm-01",
  # "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Compute/virtualMachines/app-vm-02",
]

# Web VM resource IDs
web_vm_ids = [
  # "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Compute/virtualMachines/web-vm-01",
]

# OS disk IDs (for Azure Disk Backup / snapshots)
app_vm_os_disk_ids = [
  # "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Compute/disks/app-vm-01_OsDisk",
]

web_vm_os_disk_ids = [
  # "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Compute/disks/web-vm-01_OsDisk",
]

app_vm_data_disk_ids = []
web_vm_data_disk_ids = []

alert_email_addresses = [
  "ops-team@example.com",
  "backup-admin@example.com",
]

# Leave empty to auto-create a new Log Analytics Workspace
log_analytics_workspace_id   = ""
log_analytics_workspace_name = "law-minitrue-backup"


