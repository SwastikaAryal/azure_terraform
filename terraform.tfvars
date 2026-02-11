enable_backup_vault = true

global_config = {
  env             = "dev"
  customer_prefix = "cgbp"
  product_id      = "SWP-0815"
  appd_id         = "APPD-304118"
  app_name        = "sto11weu"
  costcenter      = "0815"
}

cloud_region             = "eastus"
location                 = "eastus"
resource_group_name      = "rg-backup-eastus"
effective_bv_custom_name = "bv-prod-eastus"
datastore_type           = "VaultStore"
redundancy               = "LocallyRedundant"

tags = {
  environment = "prod"
  owner       = "devops"
  project     = "backup"
}

naming_file_json_tpl = "./naming.json.tpl"

monitoring = {
  action_group = {
    name                = "ag-backup-alerts"
    short_name          = "bkpalrt"
    resource_group_name = "rg-backup-eastus"
    
    webhook_receivers = [
      {
        name        = "backup-webhook"
        service_uri = "https://example.com/azure/backup/webhook"
      }
    ]
  }

  metric_alert = {
    name                = "backup-failure-alert"
    resource_group_name = "rg-backup-eastus"
    scopes              = ["/subscriptions/00000000-0000-0000-0000-000000000000"]
    description         = "Alert when backup jobs fail"

    criteria = {
      metric_namespace = "Microsoft.RecoveryServices/vaults"
      metric_name      = "BackupFailure"
      aggregation      = "Total"
      operator         = "GreaterThan"
      threshold        = 0

      dimension = {
        name     = "BackupInstanceName"
        operator = "Include"
        values   = ["*"]
      }
    }
  }
}
