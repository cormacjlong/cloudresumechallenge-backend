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
