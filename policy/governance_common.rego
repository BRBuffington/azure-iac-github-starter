# Shared helpers for the `governance` policy package. These rules run against
# `terraform show -json` plan output (the same input as no_unexpected_destroy).
#
# All governance policies are PARAMS-DRIVEN and inert when their parameter is
# absent, so a team enables/scopes each guardrail by editing
# policy/governance.params.json (passed to conftest via `--data`). Shipping them
# on with sensible defaults, off when unconfigured.
package governance

import rego.v1

# Resource changes that CREATE or UPDATE a resource. Deletes, reads, and no-ops
# are skipped so a guardrail never fires on a resource being removed.
managed_resources contains rc if {
	some rc in input.resource_changes
	some action in rc.change.actions
	action in {"create", "update"}
}
