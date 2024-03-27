data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

# Naming module to ensure all resources have naming standard applied
module "naming" {
  source      = "Azure/naming/azurerm"
  suffix      = [var.env, var.project_prefix]
  unique-seed = data.azurerm_subscription.current.subscription_id
}

# Get the Managed User Identity
data "azurerm_user_assigned_identity" "mid" {
  name                = var.managed_identity_name
  resource_group_name = var.managed_identity_resource_group
}

# Create a resource group to host the backend resources
resource "azurerm_resource_group" "rg" {
  location = var.resource_location
  name     = module.naming.resource_group.name
}

# Create Storage Account to host the Function App
resource "azurerm_storage_account" "sa" {
  name                     = module.naming.storage_account.name_unique
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Create  App Service Plan with serverless pricing tier
resource "azurerm_service_plan" "asp" {
  location            = azurerm_resource_group.rg.location
  name                = module.naming.app_service_plan.name
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"
  sku_name            = "Y1"
}

# Create the Function App
resource "azurerm_linux_function_app" "func" {
  location                   = azurerm_resource_group.rg.location
  name                       = module.naming.function_app.name_unique
  resource_group_name        = azurerm_resource_group.rg.name
  service_plan_id            = azurerm_service_plan.asp.id
  storage_account_name       = azurerm_storage_account.sa.name
  storage_account_access_key = azurerm_storage_account.sa.primary_access_key
  https_only                 = true

  site_config {
    ftps_state = "FtpsOnly"
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME = "python"
  }
}

# Create CosmosDB account
resource "azurerm_cosmosdb_account" "cosmosdb" {
  name                      = module.naming.cosmosdb_account.name_unique
  location                  = azurerm_resource_group.rg.location
  resource_group_name       = azurerm_resource_group.rg.name
  offer_type                = "Standard"
  kind                      = "GlobalDocumentDB"
  enable_automatic_failover = false
  enable_free_tier          = true
  minimal_tls_version       = "Tls12"
  consistency_policy {
    consistency_level       = "BoundedStaleness"
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }
  geo_location {
    location          = azurerm_resource_group.rg.location
    failover_priority = 0
  }
  capabilities {
    name = "EnableServerless"
  }
  capabilities {
    name = "EnableTable"
  }
}

# Create a Role Assignment for the Managed Identity to access the CosmosDB account
resource "azurerm_role_assignment" "cosmosdb_role_assignment" {
  scope                = azurerm_cosmosdb_account.cosmosdb.id
  role_definition_name = "Cosmos DB Operator"
  principal_id         = data.azurerm_user_assigned_identity.mid.principal_id
}

# Create a container in the CosmosDB account
resource "azurerm_cosmosdb_sql_container" "container" {
  name                = "items"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmosdb.name
  database_name       = "items"
  partition_key_path  = "/id"
  throughput          = 400
  depends_on          = [azurerm_role_assignment.cosmosdb_role_assignment]
}
