// Test Setup Module - Create prerequisites for testing
// Location: tests/setup/main.tf

terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "random" {}

// ============================================================================
// Random suffix for unique naming
// ============================================================================
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

// ============================================================================
// Resource Group
// ============================================================================
resource "azurerm_resource_group" "test" {
  name     = "rg-backup-vault-test-${random_string.suffix.result}"
  location = "eastus"

  tags = {
    Environment = "Test"
    ManagedBy   = "Terraform"
    Purpose     = "BackupVaultTesting"
  }
}

// ============================================================================
// Log Analytics Workspace for Diagnostic Settings
// ============================================================================
resource "azurerm_log_analytics_workspace" "test" {
  name                = "law-backup-test-${random_string.suffix.result}"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    Environment = "Test"
    ManagedBy   = "Terraform"
  }
}

// ============================================================================
// Virtual Network for Private Endpoints
// ============================================================================
resource "azurerm_virtual_network" "test" {
  name                = "vnet-backup-test-${random_string.suffix.result}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name

  tags = {
    Environment = "Test"
    ManagedBy   = "Terraform"
  }
}

resource "azurerm_subnet" "test" {
  name                = "subnet-private-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.test.name
  virtual_network_name = azurerm_virtual_network.test.name
  address_prefixes     = ["10.0.1.0/24"]

  private_endpoint_network_policies_enabled             = false
  private_link_service_network_policies_enabled         = false
}

// ============================================================================
// Key Vault for CMK Testing
// ============================================================================
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "test" {
  name                = "kv-backup-test-${random_string.suffix.result}"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  enabled_for_disk_encryption        = true
  enabled_for_template_deployment    = true
  enabled_for_deployment             = true
  purge_protection_enabled           = true
  soft_delete_retention_days         = 90

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get",
      "Create",
      "Delete",
      "List",
      "Restore",
      "Recover",
      "UnwrapKey",
      "WrapKey",
      "Purge",
      "Encrypt",
      "Decrypt",
      "Sign",
      "Verify"
    ]
  }

  tags = {
    Environment = "Test"
    ManagedBy   = "Terraform"
  }
}

resource "azurerm_key_vault_key" "backup_vault_cmk" {
  name            = "backup-vault-key"
  key_vault_id    = azurerm_key_vault.test.id
  key_type        = "RSA"
  key_size        = 2048
  expiration_date = timeadd(now(), "87600h") // 10 years

  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey"
  ]

  tags = {
    Purpose = "BackupVaultEncryption"
  }
}

// ============================================================================
// Storage Account for Blob Backup Testing
// ============================================================================
resource "azurerm_storage_account" "test" {
  name                     = "stbackuptest${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.test.name
  location                 = azurerm_resource_group.test.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  tags = {
    Environment = "Test"
    ManagedBy   = "Terraform"
  }
}

resource "azurerm_storage_container" "test" {
  name                  = "container1"
  storage_account_name  = azurerm_storage_account.test.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "test" {
  name                   = "test-blob.txt"
  storage_account_name   = azurerm_storage_account.test.name
  storage_container_name = azurerm_storage_container.test.name
  type                   = "Block"
  source_content         = "Test backup content"
}

// ============================================================================
// Managed Disk for Disk Backup Testing
// ============================================================================
resource "azurerm_managed_disk" "test" {
  name                = "disk-backup-test-${random_string.suffix.result}"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 32

  tags = {
    Environment = "Test"
    ManagedBy   = "Terraform"
  }
}

// ============================================================================
// PostgreSQL Server for Database Backup Testing
// ============================================================================
resource "azurerm_postgresql_server" "test" {
  name                = "pgserver-backup-test-${random_string.suffix.result}"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name

  sku_name = "B_Gen5_1"

  storage_mb                   = 51200
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  administrator_login          = "adminuser"
  administrator_login_password = random_password.postgres.result

  ssl_enforcement_enabled = true
  version                 = "14"

  tags = {
    Environment = "Test"
    ManagedBy   = "Terraform"
  }
}

resource "random_password" "postgres" {
  length  = 16
  special = true
}

resource "azurerm_postgresql_database" "test" {
  name                = "testdb"
  resource_group_name = azurerm_resource_group.test.name
  server_name         = azurerm_postgresql_server.test.name
  charset             = "UTF8"
  collation           = "en_US.utf8"
}

// ============================================================================
// PostgreSQL Flexible Server for Flexible Database Backup Testing
// ============================================================================
resource "azurerm_postgresql_flexible_server" "test" {
  name                   = "pgflex-backup-test-${random_string.suffix.result}"
  resource_group_name    = azurerm_resource_group.test.name
  location               = azurerm_resource_group.test.location
  administrator_login    = "adminuser"
  administrator_password = random_password.postgres_flex.result
  version                = "14"
  sku_name               = "B_Standard_B1ms"

  storage_mb = 32768
  backup_retention_days = 7

  tags = {
    Environment = "Test"
    ManagedBy   = "Terraform"
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.test]
}

resource "random_password" "postgres_flex" {
  length  = 16
  special = true
}

resource "azurerm_postgresql_flexible_server_database" "test" {
  name       = "testdb"
  server_id  = azurerm_postgresql_flexible_server.test.id
  charset    = "UTF8"
  collation  = "en_US.utf8"
}

// ============================================================================
// Private DNS Zone for PostgreSQL Flexible Server
// ============================================================================
resource "azurerm_private_dns_zone" "postgresql" {
  name                = "private.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.test.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "test" {
  name                  = "vnet-link"
  private_dns_zone_name = azurerm_private_dns_zone.postgresql.name
  virtual_network_id    = azurerm_virtual_network.test.id
  resource_group_name   = azurerm_resource_group.test.name
}

// ============================================================================
// Outputs for Test Module
// ============================================================================
output "resource_group_name" {
  value       = azurerm_resource_group.test.name
  description = "Test resource group name"
}

output "resource_group_id" {
  value       = azurerm_resource_group.test.id
  description = "Test resource group ID"
}

output "log_analytics_workspace_id" {
  value       = azurerm_log_analytics_workspace.test.id
  description = "Log Analytics workspace ID for diagnostic settings"
}

output "key_vault_id" {
  value       = azurerm_key_vault.test.id
  description = "Key Vault ID for CMK testing"
}

output "key_vault_key_name" {
  value       = azurerm_key_vault_key.backup_vault_cmk.name
  description = "Key Vault key name for CMK"
}

output "virtual_network_id" {
  value       = azurerm_virtual_network.test.id
  description = "Virtual Network ID for private endpoints"
}

output "subnet_id" {
  value       = azurerm_subnet.test.id
  description = "Subnet ID for private endpoints"
}

output "storage_account_id" {
  value       = azurerm_storage_account.test.id
  description = "Storage account ID for blob backup testing"
}

output "storage_container_name" {
  value       = azurerm_storage_container.test.name
  description = "Storage container name for blob backup"
}

output "disk_id" {
  value       = azurerm_managed_disk.test.id
  description = "Managed disk ID for disk backup testing"
}

output "postgres_server_id" {
  value       = azurerm_postgresql_server.test.id
  description = "PostgreSQL server ID for database backup testing"
}

output "postgres_database_id" {
  value       = azurerm_postgresql_database.test.id
  description = "PostgreSQL database ID for database backup testing"
}

output "postgres_flex_server_id" {
  value       = azurerm_postgresql_flexible_server.test.id
  description = "PostgreSQL flexible server ID for database backup testing"
}

output "postgres_flex_database_id" {
  value       = azurerm_postgresql_flexible_server_database.test.id
  description = "PostgreSQL flexible server database ID"
}
