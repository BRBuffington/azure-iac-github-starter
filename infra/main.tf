# Minimal skeleton — replace with your landing-zone layers (prefer Azure Verified
# Modules: https://aka.ms/avm). This exists only so the pipeline runs end-to-end.

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.scope}-${var.region_alias}-${var.environment}"
  location = var.location
  tags     = var.tags
}

# Example placeholder resource. Swap for your real landing-zone modules.
# resource "azurerm_log_analytics_workspace" "this" {
#   name                = "log-${var.scope}-${var.region_alias}-${var.environment}"
#   resource_group_name = azurerm_resource_group.this.name
#   location            = azurerm_resource_group.this.location
#   sku                 = "PerGB2018"
#   retention_in_days   = 30
#   tags                = var.tags
# }
