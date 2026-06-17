package governance

import rego.v1

_rt_iso(extra) := object.union(
	{"enforce_private_network": false, "enforce_secure_transport": false, "allowed_regions": []},
	extra,
)

_rt_rg(tags) := {"resource_changes": [{
	"address": "azurerm_resource_group.this",
	"type": "azurerm_resource_group",
	"change": {"actions": ["create"], "after": {"tags": tags}},
}]}

test_all_required_tags_present_passes if {
	count(deny) == 0 with input as _rt_rg({"environment": "prd", "owner": "platform"})
		with data.params as _rt_iso({"required_tags": ["environment", "owner"]})
}

test_missing_tag_denied if {
	count(deny) == 1 with input as _rt_rg({"environment": "prd"})
		with data.params as _rt_iso({"required_tags": ["environment", "owner"]})
}

test_inert_when_no_required_tags if {
	count(deny) == 0 with input as _rt_rg({})
		with data.params as _rt_iso({"required_tags": []})
}

test_invalid_tag_value_denied if {
	count(deny) == 1 with input as _rt_rg({"environment": "staging", "owner": "x"})
		with data.params as _rt_iso({
			"required_tags": ["environment", "owner"],
			"tag_allowed_values": {"environment": ["dev", "tst", "prd"]},
		})
}

test_valid_tag_value_passes if {
	count(deny) == 0 with input as _rt_rg({"environment": "prd", "owner": "x"})
		with data.params as _rt_iso({
			"required_tags": ["environment", "owner"],
			"tag_allowed_values": {"environment": ["dev", "tst", "prd"]},
		})
}

test_untagged_enforced_type_with_no_tags_denied if {
	plan := {"resource_changes": [{
		"address": "azurerm_resource_group.this", "type": "azurerm_resource_group",
		"change": {"actions": ["create"], "after": {}},
	}]}
	count(deny) == 1 with input as plan
		with data.params as _rt_iso({"required_tags": ["environment"]})
}

test_non_enforced_type_ignored if {
	plan := {"resource_changes": [{
		"address": "azurerm_storage_account.this", "type": "azurerm_storage_account",
		"change": {"actions": ["create"], "after": {"tags": {}}},
	}]}
	count(deny) == 0 with input as plan
		with data.params as _rt_iso({"required_tags": ["environment"]})
}
