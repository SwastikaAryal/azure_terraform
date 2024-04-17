# 1. Specify the version of the AzureRM Provider to use
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0, < 4.0"
    }
  }
}

# 2. Configure the AzureRM Provider
provider "azurerm" {
  features {}
  skip_provider_registration = true
}