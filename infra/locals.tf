# Provenance tags, merged into every resource via local.common_tags.
#
# DeployedByRepo records the owning repository (owner/name) so an agent — or a
# human weeks later — can answer "what deployed this, and from where?" straight
# off the resource, with no state access. CI sets it from github.repository;
# off-pipeline (local read-only) runs fall back to the var default ("local").
#
# LastApplied is intentionally NOT set here. It is stamped post-apply by the
# stamp-last-applied CD job (az tag update --operation Merge, value = the UTC
# apply date), and every taggable resource carries
# `lifecycle { ignore_changes = [tags["LastApplied"]] }` so the stamp reflects
# only on apply and never shows up as plan drift. A dynamic, post-create value
# cannot live in the Terraform tag map without churning every plan.
locals {
  common_tags = merge(var.tags, {
    DeployedByRepo = var.deployed_by_repo
  })
}
