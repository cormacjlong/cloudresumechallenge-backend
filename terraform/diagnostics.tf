module "config_diagnostics" {
  count                      = var.logging_on ? 1 : 0
  source                     = "./modules/diagnostics"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this[0].id
  targets_resource_id = [azurerm_log_analytics_workspace.this[0].id,
    azurerm_service_plan.this.id,
    azurerm_linux_function_app.this.id,
    azurerm_storage_account.this.id,
    join("", [azurerm_storage_account.this.id, "/blobServices/default"]),
    join("", [azurerm_storage_account.this.id, "/queueServices/default"]),
    join("", [azurerm_storage_account.this.id, "/tableServices/default"]),
  join("", [azurerm_storage_account.this.id, "/fileServices/default"])]
}
