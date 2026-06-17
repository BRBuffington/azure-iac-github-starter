package governance

import rego.v1

_ar_iso(extra) := object.union(
	{"enforce_private_network": false, "enforce_secure_transport": false, "required_tags": []},
	extra,
)

_ar_rg(loc) := {"resource_changes": [{
	"address": "azurerm_resource_group.this",
	"type": "azurerm_resource_group",
	"change": {"actions": ["create"], "after": {"location": loc}},
}]}

test_allowed_region_passes if {
	count(deny) == 0 with input as _ar_rg("eastus")
		with data.params as _ar_iso({"allowed_regions": ["eastus", "eastus2"]})
}

test_disallowed_region_denied if {
	count(deny) == 1 with input as _ar_rg("westus")
		with data.params as _ar_iso({"allowed_regions": ["eastus", "eastus2"]})
}

test_region_match_is_case_insensitive if {
	count(deny) == 0 with input as _ar_rg("EastUS")
		with data.params as _ar_iso({"allowed_regions": ["eastus"]})
}

test_inert_when_no_allowed_list if {
	count(deny) == 0 with input as _ar_rg("westus")
		with data.params as _ar_iso({"allowed_regions": []})
}

test_skips_deleted_resource if {
	plan := {"resource_changes": [{
		"address": "azurerm_resource_group.this", "type": "azurerm_resource_group",
		"change": {"actions": ["delete"], "after": null},
	}]}
	count(deny) == 0 with input as plan
		with data.params as _ar_iso({"allowed_regions": ["eastus"]})
}
