terraform {
  required_version = ">=1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.7.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~>3.0"
    }
  }
  backend "azurerm" {
    resource_group_name  = "rg-terraform"
    storage_account_name = "stcjlterraform"
    container_name       = "tfstate"
    key                  = "crc.tfstate"
    use_oidc             = true
  }
}

# Configure the Microsoft Azure Provider.
provider "azurerm" {
  use_oidc = true
  features {}
}