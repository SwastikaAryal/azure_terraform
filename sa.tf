# =================================================================================================
# File: terraform/modules/storage_account/terraform.tfvars
# =================================================================================================

# Global Configuration
global_config = {
  project     = "myproject"
  environment = "prod"
  region      = "westeurope"
}

cloud_region        = "westeurope"
resource_group_name = "rg-storage-prod-westeurope"

# Storage Account Configuration
account_tier             = "Standard"
account_replication_type = "GRS"
account_kind             = "StorageV2"

# Security Settings
public_network_access_enabled   = false
shared_access_key_enabled       = false
default_to_oauth_authentication = true

# Customer Managed Key (CMK) Configuration
enable_cmk                      = true
cmk_key_name                    = "storage-encryption-key"
cmk_key_vault_id                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-keyvault-prod/providers/Microsoft.KeyVault/vaults/kv-prod-westeurope"
cmk_user_assigned_identity_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-identity-prod/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-storage-cmk"

# Diagnostic Settings
create_diagnostic_settings = true
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring-prod/providers/Microsoft.OperationalInsights/workspaces/law-prod-westeurope"

# Storage Properties
queue_properties = {
  logging = {
    delete                = true
    read                  = true
    write                 = true
    version               = "1.0"
    retention_policy_days = 10
  }
}

blob_properties = {
  versioning_enabled       = true
  change_feed_enabled      = true
  last_access_time_enabled = true
  delete_retention_policy = {
    days = 30
  }
  container_delete_retention_policy = {
    days = 30
  }
}

share_properties = {
  retention_policy = {
    days = 30
  }
}

# Naming and Tagging
custom_name_suffix   = "data"
naming_file_json_tpl = "./naming-template.json"

tags = {
  Environment  = "Production"
  Project      = "DataPlatform"
  ManagedBy    = "Terraform"
  CostCenter   = "IT-001"
  Owner        = "data-team@company.com"
  Compliance   = "GDPR"
}

# Network Configuration
allowed_ips = [
  "203.0.113.0/24",  # Office Network
  "198.51.100.50"    # VPN Gateway
]

allowed_subnet_ids = [
  "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-prod/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/snet-data",
  "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-prod/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/snet-app"
]

create_private_endpoint = true

# Storage Management Policy
storage_management_policy = {
  rules = [
    {
      name    = "move-to-cool-tier"
      enabled = true
      filters = {
        prefix_match = ["container1/logs"]
        blob_types   = ["blockBlob"]
      }
      actions = {
        base_blob = {
          tier_to_cool_after_days_since_modification_greater_than = 30
          tier_to_archive_after_days_since_modification_greater_than = 90
          delete_after_days_since_modification_greater_than = 365
        }
        snapshot = {
          delete_after_days_since_creation_greater_than = 90
        }
        version = {
          change_tier_to_cool_after_days_since_creation = 30
          delete_after_days_since_creation = 90
        }
      }
    },
    {
      name    = "delete-old-backups"
      enabled = true
      filters = {
        prefix_match = ["backups/"]
        blob_types   = ["blockBlob"]
        match_blob_index_tag = {
          name      = "Retention"
          operation = "=="
          value     = "Short"
        }
      }
      actions = {
        base_blob = {
          delete_after_days_since_modification_greater_than = 90
        }
      }
    },
    {
      name    = "archive-cold-data"
      enabled = true
      filters = {
        prefix_match = ["archive/"]
        blob_types   = ["blockBlob"]
      }
      actions = {
        base_blob = {
          tier_to_cool_after_days_since_modification_greater_than = 7
          tier_to_archive_after_days_since_modification_greater_than = 30
        }
        snapshot = {
          change_tier_to_archive_after_days_since_creation = 30
          delete_after_days_since_creation_greater_than = 180
        }
      }
    }
  ]
}

# Monitoring Configuration
monitoring = {
  enabled = true
  action_group = {
    name       = "ag-storage-alerts-prod"
    short_name = "stg-alerts"
    webhook_receivers = [
      {
        name                    = "teams-webhook"
        service_uri             = "https://outlook.office.com/webhook/xxxxx"
        use_common_alert_schema = true
      }
    ]
    email_receivers = [
      {
        name                    = "ops-team"
        email_address           = "ops-team@company.com"
        use_common_alert_schema = true
      },
      {
        name                    = "security-team"
        email_address           = "security@company.com"
        use_common_alert_schema = true
      }
    ]
  }
  metric_alert = {
    name        = "alert-storage-availability"
    scopes      = [module.bmw_storage_account.id]  # This will need to be set after initial deployment
    description = "Alert when storage account availability drops below threshold"
    severity    = 2
    frequency   = "PT5M"
    window_size = "PT15M"
    enabled     = true
    criteria = {
      metric_namespace = "Microsoft.Storage/storageAccounts"
      metric_name      = "Availability"
      aggregation      = "Average"
      operator         = "LessThan"
      threshold        = 99.9
      dimension = {
        name     = "ApiName"
        operator = "Include"
        values   = ["*"]
      }
    }
  }
}

# Security Configuration
enable_defender_for_storage = true
