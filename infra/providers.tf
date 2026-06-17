terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Backend values are supplied at init time via -backend-config (see
  # backend.hcl.example and the workflows). Keeping the block empty here keeps
  # the per-config state key out of source control.
  backend "azurerm" {}
}

provider "azurerm" {
  subscription_id     = var.subscription_id
  storage_use_azuread = true # Entra auth to the state account; no shared keys
  features {}
}
