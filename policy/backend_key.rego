# State-safety gate (1 of 2): enforce the per-config remote-state convention.
#
# Every config gets its OWN nested state file `<prefix>/<config>.tfstate`. A flat
# key (`<name>.tfstate`, no slash) is the "laptop-style" state that silently
# diverges from the CD pipeline's per-config blob: the pipeline init's against an
# empty `<prefix>/<config>.tfstate` while the real state sits in a flat
# `<name>.tfstate`, so the plan proposes rebuilding the entire stack.
#
# Pre-plan check. Input is the backend key the pipeline is about to init against:
#   {"key": "<prefix>/<config>.tfstate"}
package backend_key

import rego.v1

# Valid = at least one nested segment, a slash, then a final config segment ending
# in `.tfstate`. Accepts mixed case (Azure blob names are case-sensitive) and
# multi-level prefixes (`team/stack/config.tfstate`). The load-bearing invariant is
# >= 1 slash, so a flat `name.tfstate` is rejected.
_valid if regex.match(`^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)+\.tfstate$`, input.key)

deny contains msg if {
	not _valid
	msg := sprintf(
		"backend key %q must be '<prefix>/<config>.tfstate' (one nested state file per config). A flat or malformed key diverges laptop vs CD state and makes plans run against empty state.",
		[input.key],
	)
}
