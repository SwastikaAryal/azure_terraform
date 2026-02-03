location                = "eastus"
resource_group_name     = "rg-backup-eastus"
effective_bv_custom_name = "bv-prod-eastus"
datastore_type          = "VaultStore"
redundancy              = "LocallyRedundant"
soft_delete_state       = "Enabled"

tags = {
  environment = "prod"
  owner       = "devops"
  project     = "backup"
}

naming_file_json_tpl = "naming.json"

monitoring = {
  action_group = {
    name            = "ag-backup-alerts"
    short_name     = "bkpalrt"
    webhook_receivers = ["backup-webhook"]
  }

  webhook_receiver = {
    name        = "backup-webhook"
    service_uri = "https://example.com/azure/backup/webhook"
  }

  metric_alert = {
    name        = "backup-failure-alert"
    scopes     = ["/subscriptions/00000000-0000-0000-0000-000000000000"]
    description = "Alert when backup jobs fail"

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
