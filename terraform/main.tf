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
  name                     = "st${replace(module.naming.function_app.name_unique, "-", "")}"
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
  location                      = azurerm_resource_group.rg.location
  name                          = module.naming.function_app.name_unique
  resource_group_name           = azurerm_resource_group.rg.name
  service_plan_id               = azurerm_service_plan.asp.id
  storage_account_name          = azurerm_storage_account.sa.name
  storage_uses_managed_identity = true
  https_only                    = true
  app_settings = {
    "ENABLE_ORYX_BUILD"              = "true"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
    "FUNCTIONS_WORKER_RUNTIME"       = "python"
    "AzureWebJobsFeatureFlags"       = "EnableWorkerIndexing"
    "cosmos_endpoint"                = azurerm_cosmosdb_account.cosmosdb.endpoint
  }
  connection_string {
    name  = "Default"
    type  = "Custom"
    value = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.kv.name};SecretName=${var.connection_string_secret_name})"
  }
  site_config {
    ftps_state                             = "FtpsOnly"
    application_insights_key               = var.logging_on == true ? azurerm_application_insights.ai[0].instrumentation_key : null
    application_insights_connection_string = var.logging_on == true ? azurerm_application_insights.ai[0].connection_string : null
    application_stack {
      python_version = "3.11"
    }
    cors {
      allowed_origins = ["https://${var.custom_url_prefix}.${var.azure_dns_zone_name}"]
    }
  }
  identity {
    type = "SystemAssigned"
  }
  lifecycle {
    ignore_changes = [
      app_settings["WEBSITE_ENABLE_SYNC_UPDATE_SITE"],
      app_settings["WEBSITE_RUN_FROM_PACKAGE"],
      tags["hidden-link: /app-insights-instrumentation-key"],
      tags["hidden-link: /app-insights-resource-id"]
    ]
  }
}

# Create a Role Assignment for the Function App to access the Storage Account
resource "azurerm_role_assignment" "func_blobowner_storage_role_assignment" {
  scope                = azurerm_storage_account.sa.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_linux_function_app.func.identity.0.principal_id
}
resource "azurerm_role_assignment" "func_accountcontributor_storage_role_assignment" {
  scope                = azurerm_storage_account.sa.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_linux_function_app.func.identity.0.principal_id
}
resource "azurerm_role_assignment" "func_queuecontributor_storage_role_assignment" {
  scope                = azurerm_storage_account.sa.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_linux_function_app.func.identity.0.principal_id
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

# Create a Role Assignment for the main Managed Identity to access the CosmosDB account
resource "azurerm_role_assignment" "main_cosmosdb_role_assignment" {
  scope                = azurerm_cosmosdb_account.cosmosdb.id
  role_definition_name = "DocumentDB Account Contributor"
  principal_id         = data.azurerm_user_assigned_identity.mid.principal_id
}

# Create a table in the CosmosDB account
resource "azurerm_cosmosdb_table" "cosmos_table" {
  name                = var.cosmos_table_name
  resource_group_name = azurerm_cosmosdb_account.cosmosdb.resource_group_name
  account_name        = azurerm_cosmosdb_account.cosmosdb.name
  depends_on          = [azurerm_role_assignment.main_cosmosdb_role_assignment]
}

# Create a Role Assignment for the main Managed Identity to access the Storage Account
resource "azurerm_role_assignment" "mi_blobowner_storage_role_assignment" {
  scope                = azurerm_storage_account.sa.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = data.azurerm_user_assigned_identity.mid.principal_id
}

# Create a Log Analytics Workspace for Application Insights
resource "azurerm_log_analytics_workspace" "law" {
  count               = var.logging_on ? 1 : 0
  location            = azurerm_resource_group.rg.location
  name                = module.naming.log_analytics_workspace.name
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 1
}

# Create Application Insights
resource "azurerm_application_insights" "ai" {
  count               = var.logging_on ? 1 : 0
  location            = azurerm_resource_group.rg.location
  name                = module.naming.application_insights.name
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "other"
  workspace_id        = azurerm_log_analytics_workspace.law[0].id
}
resource "azurerm_monitor_action_group" "ag" {
  name                = "Application Insights Smart Detection"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "aisd"
}
resource "azurerm_monitor_smart_detector_alert_rule" "failure_anomalies" {
  name                = "Failure Anomalies - ${azurerm_application_insights.application_insights.name}"
  resource_group_name = azurerm_resource_group.rg.name
  detector_type       = "FailureAnomaliesDetector"
  scope_resource_ids  = [azurerm_application_insights.ai[0].id]
  severity            = "Sev0"
  frequency           = "PT1M"
  action_group {
    ids = [azurerm_monitor_action_group.ag.id]
  }
}

# Create Keyvault
resource "azurerm_key_vault" "kv" {
  location                        = azurerm_resource_group.rg.location
  name                            = module.naming.key_vault.name_unique
  resource_group_name             = azurerm_resource_group.rg.name
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  sku_name                        = "standard"
  enabled_for_disk_encryption     = true
  enabled_for_deployment          = true
  enabled_for_template_deployment = true
  purge_protection_enabled        = false
  enable_rbac_authorization       = true
}

# Create a Role Assignment for the Function App Managed Identity to access the Keyvault
resource "azurerm_role_assignment" "func_cosmosdb_role_assignment" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.func.identity.0.principal_id
}

# Create a Role Assignment for the main Managed Identity to access the Keyvault
resource "azurerm_role_assignment" "mi_keyvault_role_assignment" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_user_assigned_identity.mid.principal_id
}

# Add Cosmos DB connection string to Keyvault
resource "azurerm_key_vault_secret" "cosmosdb_connection_string" {
  name         = var.connection_string_secret_name
  value        = "DefaultEndpointsProtocol=https;AccountName=${azurerm_cosmosdb_account.cosmosdb.name};AccountKey=${azurerm_cosmosdb_account.cosmosdb.primary_key};TableEndpoint=https://${azurerm_cosmosdb_account.cosmosdb.name}.table.cosmos.azure.com:443/;"
  key_vault_id = azurerm_key_vault.kv.id
  depends_on   = [azurerm_role_assignment.mi_keyvault_role_assignment]
}
