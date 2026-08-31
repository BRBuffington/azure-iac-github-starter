terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  features {}
}

provider "azapi" {
  subscription_id = var.subscription_id
}

provider "github" {
  owner = var.github_organization
}
