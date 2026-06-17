# State migration runbook — flat key → per-config key

Use this **once per stack** when a Terraform stack was first applied from a laptop (or
any pre-CI path) and its state landed in a **flat** backend key (`<stack>.tfstate`),
but the pipeline init's against a **per-config** key (`<prefix>/<config>.tfstate`).

## Symptom

The first CD plan on a stack you KNOW is live comes back as a near-total rebuild, e.g.:

```
Plan: 28 to add, 0 to change, 2 to destroy
```

That is the pipeline planning against an **empty** `<prefix>/<config>.tfstate` while the
real state sits in a flat `<stack>.tfstate`. Do NOT apply it — it would duplicate or
fight the live infrastructure. (The OPA `no_unexpected_destroy` gate will block it.)

## Fix (attended, one-time)

The `state-migrate.yml` workflow does this with Terraform-native backend migration
(`init -migrate-state -force-copy`) over the azurerm backend's OIDC auth — **no Azure
CLI required**, so it works on a self-hosted in-VNet runner against private-endpoint-only
state.

1. Confirm the live state's real (flat) key and the target per-config key.
2. Run the **state-migrate** workflow (workflow_dispatch) with:
   - `source_key` = the flat key, e.g. `stack.tfstate`
   - `dest_key`   = `<prefix>/<config>.tfstate`
   - `min_resources` = a sanity floor (e.g. the count you expect)
   - `allow_overwrite_dest` = false (leave false unless you intend to overwrite)
3. The job: guards that the destination is empty, inits against the source, verifies the
   source has >= `min_resources`, **uploads a state backup artifact**, then copies
   source → dest. **Terraform never deletes the source** — it stays as a rollback.
4. **Verify:** run `terraform-cd` plan-only for that config. A clean **"No changes"**
   (or only the intended drift) confirms the migration. A still-empty state would
   re-trigger the OPA mass-create deny.

## Rollback

The source blob is untouched and a `terraform state pull` backup is attached to the
migration run as `source-state-backup`. To roll back, re-point the pipeline at the
source key (or restore the backup) — nothing was destroyed.

## Prevent recurrence

- Always init with a **nested** key (`<prefix>/<config>.tfstate`). The OPA
  `backend_key` policy rejects a flat key.
- Never mix a per-config key with `terraform workspace` — that creates a separate
  orphan state at `<key>env:<config>`. Pick one mechanism, not both.
