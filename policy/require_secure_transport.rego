# Encryption in transit: deny a storage account that allows plaintext HTTP or a
# TLS version below 1.2. Supports the encryption-in-transit mandate common to
# regulated regimes (PHI, PCI-DSS, and similar).
#
# Config (policy/governance.params.json):
#   "enforce_secure_transport": true   # default on; set false to disable
package governance

import rego.v1

# HTTPS-only must be enabled (the azurerm default is true; this catches an
# explicit downgrade to false).
deny contains msg if {
	object.get(data.params, "enforce_secure_transport", true)
	some rc in managed_resources
	rc.type == "azurerm_storage_account"
	rc.change.after.https_traffic_only_enabled == false
	msg := sprintf("transport: storage account %q allows HTTP (https_traffic_only_enabled = false).", [rc.address])
}

# Minimum TLS must be 1.2 or higher.
deny contains msg if {
	object.get(data.params, "enforce_secure_transport", true)
	some rc in managed_resources
	rc.type == "azurerm_storage_account"
	tls := object.get(rc.change.after, "min_tls_version", "TLS1_2")
	not tls in {"TLS1_2", "TLS1_3"}
	msg := sprintf("transport: storage account %q sets min_tls_version = %q (require TLS1_2 or higher).", [rc.address, tls])
}
