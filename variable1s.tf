###############################################################################
# variables.tf – FSAM UAT DR Restore
###############################################################################

variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID for FSAM UAT environment"
}

variable "tenant_id" {
  type        = string
  description = "Azure Active Directory Tenant ID"
}

variable "location" {
  type        = string
  default     = "East US"
  description = "Primary Azure region where all resources are deployed"
}

variable "resource_group_name" {
  type        = string
  default     = "FSAM-UAT-RG"
  description = "Resource group containing all FSAM UAT infrastructure"
}

# ── Existing resource names ───────────────────────────────────────────────────

variable "rsv_name" {
  type        = string
  default     = "fsamuat-rsv"
  description = "Name of the existing Recovery Services Vault in the Azure portal"
}

variable "keyvault_name" {
  type        = string
  default     = "fsamuat-kvprivatebmw"
  description = "Name of the existing Key Vault in the Azure portal"
}

variable "storage_account_name" {
  type        = string
  default     = "fsamuatbackupsa"
  description = "Name of the existing Storage Account used for RSV backup staging"
}

variable "vnet_name" {
  type        = string
  default     = "fsamuat-vnet"
  description = "Name of the existing Virtual Network in the Azure portal"
}

variable "nsg_name" {
  type        = string
  default     = "fsamuat-app-nsg"
  description = "Name of the existing Network Security Group attached to the app subnet"
}

variable "vm_name" {
  type        = string
  default     = "fsam-uat-vm"
  description = "Name of the existing Windows Virtual Machine running the FSAM UAT app"
}

variable "lb_name" {
  type        = string
  default     = "fsamuat-lb"
  description = "Name of the existing Load Balancer fronting the FSAM UAT VM"
}

variable "ssl_cert_name" {
  type        = string
  default     = "fsamuat-ssl-cert"
  description = "Name of the SSL certificate stored in Key Vault for IIS HTTPS binding"
}

variable "law_name" {
  type        = string
  default     = "fsamuat-law"
  description = "Name of the existing Log Analytics Workspace for monitoring and diagnostics"
}

# ── Identities ────────────────────────────────────────────────────────────────

variable "dr_operator_object_id" {
  type        = string
  description = "AAD Object ID of the DR operator. Gets Backup Operator role on the RSV. Get via: az ad user show --id <email> --query id -o tsv"
}

variable "app_managed_identity_principal_id" {
  type        = string
  description = "Principal ID of the app VM Managed Identity. Gets Key Vault Secrets User role. Get via: az vm identity show --name fsam-uat-vm --resource-group FSAM-UAT-RG --query principalId -o tsv"
}

variable "admin_object_ids" {
  type        = list(string)
  default     = []
  description = "List of AAD Object IDs (DBA and infra lead) granted Key Vault Administrator role to re-populate secrets after restore"
}

# ── Alerts ────────────────────────────────────────────────────────────────────

variable "alert_email" {
  type        = string
  default     = "azure-infra@bmwgroup.net"
  description = "Email address for the Azure Monitor Action Group. All DR alerts across Steps 1–9b fire to this address."
}

# ── Gap fix: KV secret placeholders ──────────────────────────────────────────

variable "sql_sa_password_placeholder" {
  type        = string
  default     = "PLACEHOLDER-SET-BY-DBA-AFTER-RESTORE"
  sensitive   = true
  description = "Placeholder value written to the sql-sa-password secret slot on first apply. Terraform manages the slot only. DBA must overwrite with real value after restore via: az keyvault secret set --vault-name fsamuat-kvprivatebmw --name sql-sa-password --value <real-pwd>"
}

variable "db_connection_string_placeholder" {
  type        = string
  default     = "PLACEHOLDER-SET-BY-DBA-AFTER-RESTORE"
  sensitive   = true
  description = "Placeholder value written to the db-connection-string secret slot on first apply. Terraform manages the slot only. DBA must overwrite with real value after restore via: az keyvault secret set --vault-name fsamuat-kvprivatebmw --name db-connection-string --value <real-conn-str>"
}

# ── Gap fix: KV private endpoint ─────────────────────────────────────────────

variable "kv_pe_subnet_name" {
  type        = string
  default     = "app-subnet"
  description = "Name of the subnet to attach the Key Vault private endpoint (fsamuat-kvprivatebmw-pe) to. Must be in fsamuat-vnet."
}

# ── Gap fix: Storage container ────────────────────────────────────────────────

variable "backup_container_name" {
  type        = string
  default     = "vm-backup-staging"
  description = "Name of the blob container in fsamuatbackupsa used as RSV backup staging area. Recreated by Terraform if deleted."
}

# ── Gap fix: NSG outbound rules ───────────────────────────────────────────────

variable "nsg_outbound_priority_start" {
  type        = number
  default     = 200
  description = "Starting priority number for Terraform-managed NSG rules (inbound SQL, inbound HTTPS, outbound Internet). Must not conflict with existing manually created rules. Valid range: 100–4096."
}

# ── Gap fix: IIS SSL binding ──────────────────────────────────────────────────

variable "iis_site_name" {
  type        = string
  default     = "Default Web Site"
  description = "IIS website name on fsam-uat-vm to re-bind the SSL certificate to after restore. Used by the CustomScriptExtension in step8_ssl.tf."
}
