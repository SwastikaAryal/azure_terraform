terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
  }
  required_version = ">= 1.5.0"
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

###############################################################################
# LOCALS
###############################################################################

locals {
  location            = var.location
  secondary_location  = var.secondary_location
  resource_group_name = var.resource_group_name
  tags = {
    Environment = var.environment
    Project     = "MINITRUE"
    ManagedBy   = "Terraform"
  }
}
