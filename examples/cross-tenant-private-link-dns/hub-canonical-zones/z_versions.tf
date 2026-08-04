terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.36"
    }
  }
}

provider "azurerm" {
  subscription_id     = var.subscription_id
  storage_use_azuread = true
  features {}
}

provider "azapi" {
  subscription_id = var.subscription_id
}

# Credential seam for cross-tenant zone links.
#
# A virtualNetworkLinks resource is a CHILD of the private DNS zone, so it is
# always created in the hub subscription no matter which tenant owns the linked
# network. The spoke tenant therefore cannot create it alone. What actually
# varies is the credential: Azure requires write permission on the private DNS
# zone AND on the virtual network, in both tenants.
#
# This alias exists so that credential can differ from the default deployment
# identity -- typically a multi-tenant service principal or a B2B guest granted
# rights in the spoke tenant. Leave cross_tenant_tenant_id null and it
# authenticates exactly like the default provider, which is correct when one
# identity already spans both tenants.
provider "azurerm" {
  alias = "cross_tenant"

  subscription_id     = var.subscription_id
  tenant_id           = var.cross_tenant_tenant_id
  storage_use_azuread = true
  features {}
}
