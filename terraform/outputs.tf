output "function_app_name" {
  value = azurerm_linux_function_app.this.name
}

output "function_app_python_version" {
  value = azurerm_linux_function_app.this.site_config[0].application_stack[0].python_version
}

