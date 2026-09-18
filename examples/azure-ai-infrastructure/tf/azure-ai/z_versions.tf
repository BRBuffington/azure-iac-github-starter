terraform {
  required_version = ">= 1.12, < 2.0"

  backend "http" {}

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.7"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.57"
    }
  }
}

provider "azurerm" {
  subscription_id     = var.subscription_id
  tenant_id           = var.tenant_id
  use_oidc            = true
  storage_use_azuread = true
  features {}
}

provider "azapi" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  use_oidc        = true
}