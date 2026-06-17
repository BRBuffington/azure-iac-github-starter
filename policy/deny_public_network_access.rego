# Private-endpoint posture: deny a created/updated resource that leaves public
# network access enabled. This is the mechanical enforcement of the landing-zone
# design intent (data-plane traffic via private endpoints, off the public
# internet) that the rest of this reference argues for.
#
# Covers the two shapes the azurerm provider uses:
#   - a boolean `public_network_access_enabled` (Key Vault, SQL server, Cosmos
#     DB, AI services, app config, and many others), and
#   - the storage-account string enum `public_network_access = "Enabled"`.
#
# Config (policy/governance.params.json):
#   "enforce_private_network": true   # default on; set false to disable
package governance

import rego.v1

# Boolean flag form (most PaaS services).
deny contains msg if {
	object.get(data.params, "enforce_private_network", true)
	some rc in managed_resources
	rc.change.after.public_network_access_enabled == true
	msg := sprintf(
		"network: %s %q sets public_network_access_enabled = true; require private endpoints (public access disabled).",
		[rc.type, rc.address],
	)
}

# Storage-account string-enum form.
deny contains msg if {
	object.get(data.params, "enforce_private_network", true)
	some rc in managed_resources
	rc.type == "azurerm_storage_account"
	lower(object.get(rc.change.after, "public_network_access", "")) == "enabled"
	msg := sprintf(
		"network: storage account %q sets public_network_access = Enabled; require private endpoints (public access disabled).",
		[rc.address],
	)
}
