data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

locals {
  custom_url_prefix_full = var.env == "prod" ? var.custom_url_prefix : "${var.custom_url_prefix}-${var.env[0]}"
  common_tags = {
    Environment        = var.env[0]
    WorkloadName       = "CloudResumeChallenge"
    DataClassification = "Public"
    Criticality        = "Non-Critical"
  }
}

# Naming module to ensure all resources have naming standard applied
module "naming" {
  source      = "Azure/naming/azurerm"
  suffix      = concat(var.env, var.project_prefix)
  unique-seed = data.azurerm_subscription.current.subscription_id
  version     = "0.4.1"
}

# Get the Managed User Identity
data "azurerm_user_assigned_identity" "this" {
  name                = var.managed_identity_name
  resource_group_name = var.mid_resource_group_name
}

# Create a resource group to host the backend resources
resource "azurerm_resource_group" "this" {
  location = var.resource_location
  name     = module.naming.resource_group.name
  tags     = local.common_tags
}

# Create Storage Account to host the Function App
resource "azurerm_storage_account" "this" {
  name                     = "st${replace(module.naming.function_app.name_unique, "-", "")}"
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = local.common_tags
}

# Create  App Service Plan with serverless pricing tier
resource "azurerm_service_plan" "this" {
  location            = azurerm_resource_group.this.location
  name                = module.naming.app_service_plan.name
  resource_group_name = azurerm_resource_group.this.name
  os_type             = "Linux"
  sku_name            = "Y1"
  tags                = local.common_tags
}

# Create the Function App
resource "azurerm_linux_function_app" "this" {
  location                      = azurerm_resource_group.this.location
  name                          = module.naming.function_app.name_unique
  resource_group_name           = azurerm_resource_group.this.name
  service_plan_id               = azurerm_service_plan.this.id
  storage_account_name          = azurerm_storage_account.this.name
  storage_uses_managed_identity = true
  https_only                    = true
  app_settings = {
    "ENABLE_ORYX_BUILD"              = "true"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
    "FUNCTIONS_WORKER_RUNTIME"       = "python"
    "AzureWebJobsFeatureFlags"       = "EnableWorkerIndexing"
    "cosmos_endpoint"                = azurerm_cosmosdb_account.this.endpoint
    "daily_memory_time_quota"        = "50000"
  }

  connection_string {
    name  = "Default"
    type  = "Custom"
    value = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.this.name};SecretName=${var.connection_string_secret_name})"
  }

  site_config {
    ftps_state                             = "FtpsOnly"
    application_insights_key               = var.logging_on == true ? azurerm_application_insights.this[0].instrumentation_key : null
    application_insights_connection_string = var.logging_on == true ? azurerm_application_insights.this[0].connection_string : null
    application_stack {
      python_version = "3.11"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags

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
resource "azurerm_role_assignment" "sa_blobowner_func" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_linux_function_app.this.identity[0].principal_id
}
resource "azurerm_role_assignment" "sa_accountcontributor_func" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_linux_function_app.this.identity[0].principal_id
}
resource "azurerm_role_assignment" "sa_queuedatacontributor_func" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_linux_function_app.this.identity[0].principal_id
}

# Create CosmosDB account
resource "azurerm_cosmosdb_account" "this" {
  name                = module.naming.cosmosdb_account.name_unique
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  minimal_tls_version = "Tls12"

  consistency_policy {
    consistency_level       = "BoundedStaleness"
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }

  geo_location {
    location          = azurerm_resource_group.this.location
    failover_priority = 0
  }

  capabilities {
    name = "EnableServerless"
  }

  capabilities {
    name = "EnableTable"
  }

  tags = local.common_tags
}

# Create a Role Assignment for the main Managed Identity to access the CosmosDB account
resource "azurerm_role_assignment" "cosmosdb_documentdbaccountcontributor_mid" {
  scope                = azurerm_cosmosdb_account.this.id
  role_definition_name = "DocumentDB Account Contributor"
  principal_id         = data.azurerm_user_assigned_identity.this.principal_id
}

# Create a table in the CosmosDB account
resource "azurerm_cosmosdb_table" "this" {
  name                = var.cosmos_table_name
  resource_group_name = azurerm_cosmosdb_account.this.resource_group_name
  account_name        = azurerm_cosmosdb_account.this.name
  depends_on          = [azurerm_role_assignment.cosmosdb_documentdbaccountcontributor_mid]
}

# Create a Role Assignment for the main Managed Identity to access the Storage Account
resource "azurerm_role_assignment" "sa_blobowner_mid" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = data.azurerm_user_assigned_identity.this.principal_id
}

# Create Keyvault
resource "azurerm_key_vault" "this" {
  location                        = azurerm_resource_group.this.location
  name                            = module.naming.key_vault.name_unique
  resource_group_name             = azurerm_resource_group.this.name
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  sku_name                        = "standard"
  enabled_for_disk_encryption     = true
  enabled_for_deployment          = true
  enabled_for_template_deployment = true
  purge_protection_enabled        = false #tfsec:ignore:azure-keyvault-no-purge
  enable_rbac_authorization       = true
  network_acls { #tfsec:ignore:azure-keyvault-specify-network-acl
    default_action = "Allow"
    bypass         = "AzureServices"
    #   ip_rules       = ["172.180.0.0/14", "172.184.0.0/14"]
  }
  tags = local.common_tags
}

# Create a Role Assignment for the Function App Managed Identity to access the Keyvault
resource "azurerm_role_assignment" "kv_secretsuser_func" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.this.identity[0].principal_id
}

# Create a Role Assignment for the main Managed Identity to access the Keyvault
resource "azurerm_role_assignment" "kv_administrator_mid" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_user_assigned_identity.this.principal_id
}

# Add Cosmos DB connection string to Keyvault
resource "azurerm_key_vault_secret" "cosmosdb_connection_string" { #tfsec:ignore:azure-keyvault-ensure-secret-expiry
  name         = var.connection_string_secret_name
  value        = "DefaultEndpointsProtocol=https;AccountName=${azurerm_cosmosdb_account.this.name};AccountKey=${azurerm_cosmosdb_account.this.primary_key};TableEndpoint=https://${azurerm_cosmosdb_account.this.name}.table.cosmos.azure.com:443/;"
  key_vault_id = azurerm_key_vault.this.id
  content_type = "Connection String"
  depends_on   = [azurerm_role_assignment.kv_administrator_mid]
  tags         = local.common_tags
}

# Get the Azure DNS Zone
data "azurerm_dns_zone" "this" {
  name                = var.azure_dns_zone_name
  resource_group_name = var.azure_dns_zone_resource_group_name
}

# Create API Management Service on Consumption Plan
resource "azurerm_api_management" "this" {
  name                = module.naming.api_management.name_unique
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  publisher_name      = "Macro-C"
  publisher_email     = "cormac@macro-c.com"

  sku_name = "Consumption_0"

  identity {
    type = "SystemAssigned"
  }
  tags = local.common_tags
}

# Get Function App Keys
data "azurerm_function_app_host_keys" "this" {
  name                = azurerm_linux_function_app.this.name
  resource_group_name = azurerm_linux_function_app.this.resource_group_name
}

# Create a Named Value for the Function App Key in APIM
resource "azurerm_api_management_named_value" "this" {
  name                = "${azurerm_linux_function_app.this.name}-key"
  display_name        = "${azurerm_linux_function_app.this.name}-key"
  resource_group_name = azurerm_api_management.this.resource_group_name
  api_management_name = azurerm_api_management.this.name
  secret              = true
  value               = data.azurerm_function_app_host_keys.this.default_function_key
  tags                = local.common_tags
}

# Create a Backend for the Function App in APIM
resource "azurerm_api_management_backend" "this" {
  name                = "${azurerm_linux_function_app.this.name}-backend"
  resource_group_name = azurerm_api_management.this.resource_group_name
  api_management_name = azurerm_api_management.this.name
  protocol            = "http"
  url                 = "https://${azurerm_linux_function_app.this.name}.azurewebsites.net/api"
  resource_id         = "https://management.azure.com${azurerm_linux_function_app.this.id}"
  credentials {
    header = {
      "x-functions-key" = "{{${azurerm_api_management_named_value.this.name}}}"
    }
  }
}

# Create an API in APIM
resource "azurerm_api_management_api" "this" {
  name                  = var.api_endpoint_name
  display_name          = var.api_endpoint_name
  resource_group_name   = azurerm_api_management.this.resource_group_name
  api_management_name   = azurerm_api_management.this.name
  revision              = "1"
  subscription_required = false
  path                  = var.api_path
  protocols             = ["https"]
}

# Create an API Operation in APIM
resource "azurerm_api_management_api_operation" "this" {
  display_name        = "get-${var.api_endpoint_name}"
  api_management_name = azurerm_api_management.this.name
  api_name            = azurerm_api_management_api.this.name
  url_template        = "/${var.api_endpoint_name}"
  resource_group_name = azurerm_api_management.this.resource_group_name
  method              = "GET"
  operation_id        = var.api_endpoint_name
}

# Create an API Operation Policy in APIM
resource "azurerm_api_management_api_operation_policy" "this" {
  api_management_name = azurerm_api_management.this.name
  api_name            = azurerm_api_management_api.this.name
  operation_id        = azurerm_api_management_api_operation.this.operation_id
  resource_group_name = azurerm_api_management.this.resource_group_name
  xml_content         = <<XML
    <policies>
      <inbound>
          <base />
          <set-backend-service id="set-backend-service" backend-id="${azurerm_api_management_backend.this.name}" />
          <rate-limit calls="50" renewal-period="300" />
          <cors allow-credentials="false">
            <allowed-origins>
                <origin>https://${local.custom_url_prefix_full}.${var.azure_dns_zone_name}</origin>
            </allowed-origins>
            <allowed-methods>
                <method>GET</method>
                <method>POST</method>
            </allowed-methods>
          </cors>
      </inbound>
      <backend>
          <base />
      </backend>
      <outbound>
          <base />
      </outbound>
      <on-error>
          <base />
      </on-error>
    </policies>
  XML
}

# Get the Domain Ownership Identifier for the APIM Gateway
data "azapi_resource_action" "get_domain_ownership_identifier" {
  type                   = "Microsoft.ApiManagement@2022-08-01"
  resource_id            = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.ApiManagement"
  action                 = "getDomainOwnershipIdentifier"
  method                 = "POST"
  response_export_values = ["*"]
}

# Create a TXT DNS record for the APIM Gateway to verify ownership of domain
resource "azurerm_dns_txt_record" "apim_gateway" {
  name                = "apimuid.${local.custom_url_prefix_full}-api"
  zone_name           = data.azurerm_dns_zone.this.name
  resource_group_name = data.azurerm_dns_zone.this.resource_group_name
  ttl                 = 300
  record {
    value = jsondecode(data.azapi_resource_action.get_domain_ownership_identifier.output).domainOwnershipIdentifier
  }
  tags = local.common_tags
}

# Create a CNAME DNS record for the APIM Gateway
resource "azurerm_dns_cname_record" "apim_gateway" {
  depends_on          = [azurerm_dns_txt_record.apim_gateway]
  name                = "${local.custom_url_prefix_full}-api"
  zone_name           = data.azurerm_dns_zone.this.name
  resource_group_name = data.azurerm_dns_zone.this.resource_group_name
  ttl                 = 300
  record              = trimprefix(azurerm_api_management.this.gateway_url, "https://")
  tags                = local.common_tags
}

# Refresh the login credentials for Azure
data "external" "login" {
  program = ["bash", "${path.module}/../scripts/refresh.sh"]
  query = {
    client_id       = data.azurerm_client_config.current.client_id
    tenant_id       = data.azurerm_client_config.current.tenant_id
    subscription_id = data.azurerm_client_config.current.subscription_id
  }
  depends_on = [azurerm_api_management.this]
}

# Add custom domain to APIM
resource "null_resource" "apim_customdomain" {
  triggers = {
    apim_name = azurerm_api_management.this.name
    rg        = azurerm_api_management.this.resource_group_name
    api_url   = substr(azurerm_dns_cname_record.apim_gateway.fqdn, 0, length(azurerm_dns_cname_record.apim_gateway.fqdn) - 1)
  }

  provisioner "local-exec" {
    command = "sleep 10 && az apim update -n ${self.triggers.apim_name} -g ${self.triggers.rg} --set hostnameConfigurations='[{\"hostName\":\"${self.triggers.api_url}\",\"type\":\"Proxy\",\"certificateSource\":\"Managed\"}]'"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "az apim update -n ${self.triggers.apim_name} -g ${self.triggers.rg} --remove hostnameConfigurations"
  }
  depends_on = [data.external.login]
}
