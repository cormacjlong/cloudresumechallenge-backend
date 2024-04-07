data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

# Naming module to ensure all resources have naming standard applied
module "naming" {
  source      = "Azure/naming/azurerm"
  suffix      = concat(var.env, var.project_prefix)
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
    //api_management_api_id = azurerm_api_management.apim.id
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
  count               = var.logging_on ? 1 : 0
  name                = "Application Insights Smart Detection"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "aisd"
}
resource "azurerm_monitor_smart_detector_alert_rule" "failure_anomalies" {
  count               = var.logging_on ? 1 : 0
  name                = "Failure Anomalies - ${azurerm_application_insights.ai[0].name}"
  resource_group_name = azurerm_resource_group.rg.name
  detector_type       = "FailureAnomaliesDetector"
  scope_resource_ids  = [azurerm_application_insights.ai[0].id]
  severity            = "Sev0"
  frequency           = "PT1M"
  action_group {
    ids = [azurerm_monitor_action_group.ag[0].id]
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

# Get the Azure DNS Zone
data "azurerm_dns_zone" "dns_zone" {
  name                = var.azure_dns_zone_name
  resource_group_name = var.azure_dns_zone_resource_group_name
}

# Create the Domain Verification Record
resource "azurerm_dns_txt_record" "funcapp-domain-verify" {
  name                = "asuid.${var.custom_url_prefix}-api"
  zone_name           = data.azurerm_dns_zone.dns_zone.name
  resource_group_name = data.azurerm_dns_zone.dns_zone.resource_group_name
  ttl                 = 300

  record {
    value = azurerm_linux_function_app.func.custom_domain_verification_id
  }
}

# Create a CNAME record for the Function App
resource "azurerm_dns_cname_record" "funcapp-domain-verify" {
  name                = "${var.custom_url_prefix}-api"
  zone_name           = data.azurerm_dns_zone.dns_zone.name
  resource_group_name = data.azurerm_dns_zone.dns_zone.resource_group_name
  ttl                 = 300
  record              = azurerm_linux_function_app.func.default_hostname
  depends_on          = [azurerm_dns_txt_record.funcapp-domain-verify]
}

# Bind custom domain to function app
resource "azurerm_app_service_custom_hostname_binding" "funcapp_custom_hostname" {
  hostname            = substr(azurerm_dns_cname_record.funcapp_dns_record.fqdn, 0, length(azurerm_dns_cname_record.funcapp_dns_record.fqdn) - 1)
  app_service_name    = azurerm_linux_function_app.func.name
  resource_group_name = azurerm_resource_group.rg.name
}

# Create Azure Managed SSL Cert for Custom Domain
resource "azurerm_app_service_managed_certificate" "funcapp_managed_cert" {
  custom_hostname_binding_id = azurerm_app_service_custom_hostname_binding.funcapp_custom_hostname.id
}

resource "azurerm_app_service_certificate_binding" "funcapp_cert_binding" {
  hostname_binding_id = azurerm_app_service_custom_hostname_binding.funcapp_custom_hostname.id
  certificate_id      = azurerm_app_service_managed_certificate.funcapp_managed_cert.id
  ssl_state           = "SniEnabled"
}

# Create API Management Service on Consumption Plan
resource "azurerm_api_management" "apim" {
  name                = module.naming.api_management.name_unique
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  publisher_name      = "Macro-C"
  publisher_email     = "cormac@macro-c.com"

  sku_name = "Consumption_0"

  identity {
    type = "SystemAssigned"
  }
}

# # Add Function App to API Management
# resource "azurerm_api_management_api" "func_app" {
#   name                = "api-${azurerm_linux_function_app.func.name}"
#   resource_group_name = azurerm_resource_group.rg.name
#   api_management_name = azurerm_api_management.apim.name
#   revision            = "1"
#   display_name        = "Visitor Counter"
#   protocols           = ["https"]
#   path                = "api/visitorcounter"

#   import {
#     content_format = "swagger-link-json"
#     content_value  = "http://${azurerm_linux_function_app.func.default_hostname}/?format=json"
#   }
# }

# # Get Function App Keys
# data "azurerm_function_app_host_keys" "this" {
#   name                = azurerm_linux_function_app.func.name
#   resource_group_name = azurerm_linux_function_app.func.resource_group_name
# }

# resource "azurerm_api_management_backend" "this" {
#   name                = "backed-${azurerm_linux_function_app.func.name}"
#   resource_group_name = azurerm_api_management.apim.resource_group_name
#   api_management_name = azurerm_api_management.apim.name
#   protocol            = "http"
#   url                 = "https://${azurerm_linux_function_app.func.name}.azurewebsites.net/api/"
#   credentials {
#     header = {
#       "x-functions-key" = "${data.azurerm_function_app_host_keys.this.default_function_key}"
#     }
#   }
# }

# resource "azurerm_api_management_api" "this" {
#   name                = "example-api"
#   resource_group_name = azurerm_resource_group.rg.name
#   api_management_name = azurerm_api_management.apim.name
#   revision            = "1"
#   display_name        = "Example API"
#   path                = "example"
#   protocols           = ["https"]
#   subscription_required = false

# }
