data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

# Naming module to ensure all resources have naming standard applied
module "naming" {
  source      = "Azure/naming/azurerm"
  suffix      = [var.env, var.project_prefix]
  unique-seed = data.azurerm_subscription.current.subscription_id
}

# Create a resource group to host the storage account and CDN profile
resource "azurerm_resource_group" "rg" {
  location = var.resource_location
  name     = "${module.naming.resource_group.name}-backend"
}

# Create Storage Account to host the Function App
resource "azurerm_storage_account" "sa" {
  name                     = module.naming.storage_account.name_unique
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Create most basic App Service Plan with serverless pricing tier
resource "azurerm_app_service_plan" "asp" {
  location            = azurerm_resource_group.rg.location
  name                = module.naming.app_service_plan.name
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "FunctionApp"
  sku {
    tier = "Dynamic"
    size = "Y1"
  }
}

# Create the Function App
resource "azurerm_function_app" "func" {
  location                   = azurerm_resource_group.rg.location
  name                       = module.naming.function_app.name
  resource_group_name        = azurerm_resource_group.rg.name
  app_service_plan_id        = azurerm_app_service_plan.asp.id
  storage_account_name       = azurerm_storage_account.sa.name
  storage_account_access_key = azurerm_storage_account.sa.primary_access_key
  version                    = "~3"
  os_type                    = "linux"

  site_config {
    linux_fx_version = "PYTHON|3.8"
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME = "python"
  }
}
