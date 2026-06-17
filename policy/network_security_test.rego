package governance

import rego.v1

_ns_iso(extra) := object.union(
	{"allowed_regions": [], "required_tags": []},
	extra,
)

_ns_res(typ, after) := {"resource_changes": [{
	"address": sprintf("%s.this", [typ]),
	"type": typ,
	"change": {"actions": ["create"], "after": after},
}]}

# --- deny_public_network_access ---

test_public_bool_true_denied if {
	count(deny) == 1 with input as _ns_res("azurerm_key_vault", {"public_network_access_enabled": true})
		with data.params as _ns_iso({"enforce_private_network": true, "enforce_secure_transport": false})
}

test_public_bool_false_passes if {
	count(deny) == 0 with input as _ns_res("azurerm_key_vault", {"public_network_access_enabled": false})
		with data.params as _ns_iso({"enforce_private_network": true, "enforce_secure_transport": false})
}

test_storage_public_enabled_denied if {
	count(deny) == 1 with input as _ns_res("azurerm_storage_account", {"public_network_access": "Enabled", "https_traffic_only_enabled": true, "min_tls_version": "TLS1_2"})
		with data.params as _ns_iso({"enforce_private_network": true, "enforce_secure_transport": true})
}

test_private_network_inert_when_disabled if {
	count(deny) == 0 with input as _ns_res("azurerm_key_vault", {"public_network_access_enabled": true})
		with data.params as _ns_iso({"enforce_private_network": false, "enforce_secure_transport": false})
}

# --- require_secure_transport ---

test_http_only_false_denied if {
	count(deny) == 1 with input as _ns_res("azurerm_storage_account", {"https_traffic_only_enabled": false, "min_tls_version": "TLS1_2", "public_network_access": "Disabled"})
		with data.params as _ns_iso({"enforce_secure_transport": true, "enforce_private_network": false})
}

test_low_tls_denied if {
	count(deny) == 1 with input as _ns_res("azurerm_storage_account", {"https_traffic_only_enabled": true, "min_tls_version": "TLS1_0", "public_network_access": "Disabled"})
		with data.params as _ns_iso({"enforce_secure_transport": true, "enforce_private_network": false})
}

test_secure_storage_passes if {
	count(deny) == 0 with input as _ns_res("azurerm_storage_account", {"https_traffic_only_enabled": true, "min_tls_version": "TLS1_2", "public_network_access": "Disabled"})
		with data.params as _ns_iso({"enforce_secure_transport": true, "enforce_private_network": true})
}

test_secure_transport_inert_when_disabled if {
	count(deny) == 0 with input as _ns_res("azurerm_storage_account", {"https_traffic_only_enabled": false, "min_tls_version": "TLS1_0", "public_network_access": "Disabled"})
		with data.params as _ns_iso({"enforce_secure_transport": false, "enforce_private_network": false})
}
