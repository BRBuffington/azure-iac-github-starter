# Decisions & learned guardrails

A living, append-only record the agent — and humans — read **before** making a
choice, so a decision is made once, not re-litigated every session. This is the
operational companion to [`docs/architecture-decisions.md`](docs/architecture-decisions.md)
(the big, cited architecture decisions): this file captures the smaller,
accumulating decisions and the gotchas you hit along the way.

> **Agent:** read this file before any non-trivial change. If a decision below
> already covers what you're about to do, follow it. After you make a new durable
> decision — or hit a gotcha worth not repeating — append an entry here.

## Decisions

Newest first. One entry per decision: `### YYYY-MM-DD — summary`, then 1–3
sentences of *why*.

### 2026-06-26 — advisory, multi-model "LLM council" PR review (provider-pluggable)
Added an optional council (`.github/workflows/llm-council.yml` + `.github/scripts/llm-council.py`):
2-3 *distinct* models independently review each PR diff and one consolidated verdict comment is
posted. Chose **advisory** (never blocks unless an adopter opts in via `COUNCIL_BLOCKING` + a
required check) so the human + `CODEOWNERS` stay the gate, and **multi-model** so no single
model's blind spot decides. Ships defaulting to GitHub Models (zero setup) but is
provider-pluggable to Azure OpenAI / OpenAI / Anthropic. Because the diff leaves the repo, the
data-governance note in `docs/llm-council.md` steers regulated/PHI repos to keep inference
in-tenant (Azure OpenAI) and validate the provider's data terms first. Self-contained,
stdlib-only, and fail-soft so an unconfigured backend never breaks a PR.

### 2026-06-26 — lint the repo's own workflows in CI (actionlint)
A workflow file can parse as valid YAML yet still be rejected by GitHub's workflow
compiler (invalid context access, an empty interpolation expression, a broken
`needs` ref), which aborts the run at startup with zero jobs and an opaque message.
`workflow-lint.yml` runs actionlint on every change to `.github/workflows/**` so
that class is caught in PR review, not after merge. actionlint is pinned to a
release (same supply-chain posture as the pinned conftest install) and shellcheck
on the hosted runner deep-checks the embedded run: scripts.

## Learned guardrails (anti-patterns — don't repeat)

Things that bit us once. Each: the symptom, then the rule that prevents it.

### A CD apply gate flipped by a null-coalesced plan-only input
**Symptom:** an apply gate that derives "apply vs plan" from a nullable
`plan_only` dispatch input via a loose comparison silently misfires. On a push the
input is null, and GitHub's loose equality coerces null against a boolean: a gate
that reads the flag with a not-equal-false test flips push-to-main into an APPLY,
and its null-coalescing mirror turns a dispatch-to-apply into a no-op.
**Rule:** gate apply on the EVENT plus an explicit boolean
(`github.event_name == 'workflow_dispatch' && inputs.apply && ...`), never on a
nullable `plan_only` expression (see the `apply` job in `terraform-cd.yml`), and
lint workflows in CI (`workflow-lint.yml`) so expression footguns surface in review.

### The agent re-created infrastructure it had already deployed
**Symptom:** the agent couldn't find a resource it built weeks earlier and
proposed re-creating it — it took three reminders. **Rule:** every resource
carries a `DeployedByRepo` tag + a post-apply `LastApplied` stamp (see
`infra/locals.tf` and the CD stamp step) so prior work is traceable off the
resource itself, and the agent reads this file before deciding.
