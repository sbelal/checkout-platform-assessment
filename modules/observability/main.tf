resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-checkout-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.tags
}

resource "azurerm_application_insights" "main" {
  name                = "appi-checkout-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"

  tags = var.tags
}

# ─── Alerting ─────────────────────────────────────────────────────────────────

resource "azurerm_monitor_metric_alert" "func_availability" {
  name                = "alert-func-availability-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [var.function_app_id]
  description         = "Action will be triggered when Function App encounters HTTP 5xx errors"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 0
  }

  tags = var.tags
}
