output "cosmos_endpoint" {
  value = azurerm_cosmosdb_account.cosmosdb.endpoint
}

output "function_app_name" {
  value = azurerm_linux_function_app.func.name
}

output "function_app_python_version" {
  value = azurerm_linux_function_app.func.site_config.0.application_stack.0.python_version
}
