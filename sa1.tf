resource "azurerm_monitor_action_group" "this" {
  name                = var.monitoring.action_group.name
  resource_group_name = var.monitoring.action_group.resource_group_name
  short_name          = var.monitoring.action_group.short_name

  dynamic "webhook_receiver" {
    for_each = var.monitoring.action_group.webhook_receivers

    content {
      name        = webhook_receiver.value.name
      service_uri = webhook_receiver.value.service_uri
    }
  }
}

resource "azurerm_monitor_metric_alert" "this" {
  name                = var.monitoring.metric_alert.name
  resource_group_name = var.monitoring.metric_alert.resource_group_name
  scopes              = var.monitoring.metric_alert.scopes
  description         = var.monitoring.metric_alert.description

  criteria {
    metric_namespace = var.monitoring.metric_alert.criteria.metric_namespace
    metric_name      = var.monitoring.metric_alert.criteria.metric_name
    aggregation      = var.monitoring.metric_alert.criteria.aggregation
    operator         = var.monitoring.metric_alert.criteria.operator
    threshold        = var.monitoring.metric_alert.criteria.threshold

    dimension {
      name     = var.monitoring.metric_alert.criteria.dimension.name
      operator = var.monitoring.metric_alert.criteria.dimension.operator
      values   = var.monitoring.metric_alert.criteria.dimension.values
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}
#################variable.tf

variable "monitoring" {
  description = "Azure Monitor Action Group and Metric Alert configuration"
  type = object({
    action_group = object({
      name                = string
      short_name          = string
      resource_group_name = string

      webhook_receivers = list(object({
        name        = string
        service_uri = string
      }))
    })

    metric_alert = object({
      name                = string
      resource_group_name = string
      scopes              = list(string)
      description         = string

      criteria = object({
        metric_namespace = string
        metric_name      = string
        aggregation      = string
        operator         = string
        threshold        = number

        dimension = object({
          name     = string
          operator = string
          values   = list(string)
        })
      })
    })
  })
}


##############tfvars
monitoring = {
  action_group = {
    name                = "example-actiongroup"
    short_name          = "exampleact"
    resource_group_name = "example-rg"

    webhook_receivers = [
      {
        name        = "callmyapi"
        service_uri = "http://example.com/alert"
      }
    ]
  }

  metric_alert = {
    name                = "example-metricalert"
    resource_group_name = "example-rg"
    scopes              = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Storage/storageAccounts/to-monitor"
    ]
    description = "Action will be triggered when Transactions count is greater than 50."

    criteria = {
      metric_namespace = "Microsoft.Storage/storageAccounts"
      metric_name      = "Transactions"
      aggregation      = "Total"
      operator         = "GreaterThan"
      threshold        = 50

      dimension = {
        name     = "ApiName"
        operator = "Include"
        values   = ["*"]
      }
    }
  }
}

output "action_group_id" {
  description = "ID of the Azure Monitor Action Group"
  value       = azurerm_monitor_action_group.this.id
}

output "metric_alert_id" {
  description = "ID of the Azure Monitor Metric Alert"
  value       = azurerm_monitor_metric_alert.this.id
}


