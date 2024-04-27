# Create a Log Analytics Workspace for Application Insights
resource "azurerm_log_analytics_workspace" "this" {
  count               = var.logging_on ? 1 : 0
  location            = azurerm_resource_group.this.location
  name                = module.naming.log_analytics_workspace.name
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 1
  tags                = local.common_tags
}

# Create Application Insights
resource "azurerm_application_insights" "this" {
  count               = var.logging_on ? 1 : 0
  location            = azurerm_resource_group.this.location
  name                = module.naming.application_insights.name
  resource_group_name = azurerm_resource_group.this.name
  application_type    = "other"
  workspace_id        = azurerm_log_analytics_workspace.this[0].id
  tags                = local.common_tags
}

resource "azurerm_monitor_action_group" "this" {
  count               = var.logging_on ? 1 : 0
  name                = "Application Insights Smart Detection"
  resource_group_name = azurerm_resource_group.this.name
  short_name          = "aisd"
  tags                = local.common_tags
}

resource "azurerm_monitor_smart_detector_alert_rule" "this" {
  count               = var.logging_on ? 1 : 0
  name                = "Failure Anomalies - ${azurerm_application_insights.this[0].name}"
  resource_group_name = azurerm_resource_group.this.name
  detector_type       = "FailureAnomaliesDetector"
  scope_resource_ids  = [azurerm_application_insights.this[0].id]
  severity            = "Sev0"
  frequency           = "PT1M"
  action_group {
    ids = [azurerm_monitor_action_group.this[0].id]
  }
  tags = local.common_tags
}

# Turning on Diagnostics Settings for all resources
module "config_diagnostics" {
  count                      = var.logging_on ? 1 : 0
  source                     = "./modules/diagnostics"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this[0].id
  targets_resource_id = [
    azurerm_log_analytics_workspace.this[0].id,
    azurerm_service_plan.this.id,
    azurerm_linux_function_app.this.id,
    azurerm_storage_account.this.id,
    join("", [azurerm_storage_account.this.id, "/blobServices/default"]),
    join("", [azurerm_storage_account.this.id, "/queueServices/default"]),
    join("", [azurerm_storage_account.this.id, "/tableServices/default"]),
    join("", [azurerm_storage_account.this.id, "/fileServices/default"]),
    azurerm_key_vault.this.id
  ]
}
