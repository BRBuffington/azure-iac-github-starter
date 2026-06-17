# Tagging governance: deny a created/updated resource (of an enforced type) that
# is missing any required tag, OR whose tag value is not in the allowed set for
# that tag. Underpins cost allocation, ownership, and data-classification
# controls (Cloud Adoption Framework tagging guidance).
#
# Ported from BRBuffington/terraform-opa-policies (post-plan/required_tags.rego),
# adapted to the conftest harness (the source reads planned_values.root_module +
# child_module and `data.shared.required_tags`; here the input is the plan JSON
# from `terraform show -json` and config is `data.params`). The source's
# value-validation (required_values) is preserved.
#
# Enforced on resource groups by default (the CAF tagging anchor); extend
# `tag_enforced_types` to cover more resource types as your org standardizes.
# Scoping by type avoids false positives on untaggable resources (role
# assignments, locks, associations).
#
# Config (policy/governance.params.json):
#   "required_tags": ["environment", "owner", "data_classification"]  # empty = off
#   "tag_enforced_types": ["azurerm_resource_group"]                  # default
#   "tag_allowed_values": { "environment": ["dev","tst","prd"] }       # optional
package governance

import rego.v1

# Missing-tag check.
deny contains msg if {
	required := data.params.required_tags
	count(required) > 0
	enforced := {t | some t in object.get(data.params, "tag_enforced_types", ["azurerm_resource_group"])}
	some rc in managed_resources
	rc.type in enforced
	tags := object.get(rc.change.after, "tags", {})
	some t in required
	not tags[t]
	msg := sprintf("tags: %s %q is missing required tag %q.", [rc.type, rc.address, t])
}

# Invalid-value check (only for tags that declare an allowed-value list).
deny contains msg if {
	required := data.params.required_tags
	count(required) > 0
	enforced := {t | some t in object.get(data.params, "tag_enforced_types", ["azurerm_resource_group"])}
	allowed_values := object.get(data.params, "tag_allowed_values", {})
	some rc in managed_resources
	rc.type in enforced
	tags := object.get(rc.change.after, "tags", {})
	some t in required
	value := tags[t]
	allowed := allowed_values[t]
	count(allowed) > 0
	not value in allowed
	msg := sprintf("tags: %s %q has invalid value %q for tag %q (allowed: %v).", [rc.type, rc.address, value, t, allowed])
}
