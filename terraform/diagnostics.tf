module "config_diagnostics" {
  count                      = var.logging_on ? 1 : 0
  source                     = "./modules/diagnostics"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law[0].id
  targets_resource_id = [azurerm_log_analytics_workspace.law[0].id,
    azurerm_service_plan.asp.id,
    azurerm_linux_function_app.func.id,
    azurerm_storage_account.sa.id,
    join("", [azurerm_storage_account.sa.id, "/blobServices/default"]),
    join("", [azurerm_storage_account.sa.id, "/queueServices/default"]),
    join("", [azurerm_storage_account.sa.id, "/tableServices/default"]),
  join("", [azurerm_storage_account.sa.id, "/fileServices/default"])]
}
