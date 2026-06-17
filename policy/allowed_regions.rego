# Data residency: deny any created/updated resource whose Azure region is not in
# the approved list. Critical for regimes that pin regulated data to specific
# geographies (for example PHI under HIPAA/HITRUST data-residency commitments).
#
# Ported from BRBuffington/terraform-opa-policies (post-plan/allowed_regions.rego),
# adapted to the conftest harness: the source reads `input.tfplan` +
# `data.shared.allowed_regions`; here the plan JSON is `input` (from
# `terraform show -json`) and the list is `data.params.allowed_regions`.
#
# Config (policy/governance.params.json):
#   "allowed_regions": ["eastus", "eastus2"]   # empty / absent = no restriction
package governance

import rego.v1

deny contains msg if {
	regions := data.params.allowed_regions
	count(regions) > 0
	allowed := {lower(r) | some r in regions}
	some rc in managed_resources
	loc := rc.change.after.location
	is_string(loc)
	not lower(loc) in allowed
	msg := sprintf(
		"region: %s %q targets region %q, which is not in allowed_regions %v (data residency).",
		[rc.type, rc.address, loc, regions],
	)
}
