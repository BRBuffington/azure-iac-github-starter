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

### 2026-08-31 — Private runner delivery has two supported ownership models
Private-endpoint delivery can use self-hosted Container Apps job runners or
GitHub-hosted larger runners attached through Azure Private Networking. Keep each
implementation in its existing runner owner and one environment per state. The APN
reference uses AVM networking and AzAPI for `GitHub.Network/networkSettings`; a narrow,
idempotent REST bridge owns only the hosted-compute association missing from GitHub
provider 6.13.0. The repository owner authorized this generic, un-applied reference on
2026-08-31; every consuming VNet, subnet, route, endpoint, identity, and GitHub scope
remains an explicit environment decision before deployment. `GitHub.Network`
registration remains in the subscription bootstrap, never a copied per-environment
root whose destroy could unregister the provider for another APN deployment.

### 2026-08-14 — Publication diagnostics collect evidence without naming the cause
The private Foundry client flow includes a read-only collector for PNA, network
injection, VNet/peer CIDRs, roles, private endpoints, and Network Watcher VNet
flow logs. Sequential 502/403 responses remain separate observations until
service-side evidence links or distinguishes them; the client script preserves
the service code and request ID instead of inferring network, RBAC, licensing,
or tenant policy.

### 2026-08-14 — Compose defaults with current Microsoft CAF abbreviations
The Foundry Bicep starter composes workload, region, and environment inputs once,
then applies Microsoft resource prefixes (`aif`, `proj`, `srch`, `cosno`, `st`,
`cr`, `appi`, `log`, `pep`, `vnet`, `snet`, and `bot`). Full-name parameters
remain available for existing resources and client-specific exceptions.

### 2026-08-14 — Use the proven Step 4 flow as a baseline, not a ceiling
Jonathan's working Bicep and PowerShell remain the client MVP and troubleshooting
path. Improve individual steps when IaC is simpler, as with Bot Service, and
default standard values so adopters supply only environment-specific resource
IDs, CIDRs, and identities while retaining explicit overrides.

### 2026-08-14 — Reuse the working private Foundry Bicep package directly
The third Foundry agent-to-Teams option preserves the already-working Bicep
foundation, network attachment, and Step 1-4 PowerShell flow rather than
reimplementing them. Only client parameter examples are generalized; the small
Step 2 Bot Service template keeps supported ARM resources in IaC.

### 2026-08-07 — Foundry public and private patterns are independent staged roots
The Foundry agent-to-Teams starter keeps public and Standard/BYO-private
architectures in separate roots and states. Terraform owns Azure resources;
repository JSON plus the human-gated data-plane workflow own immutable toolbox
versions, Prompt Agent versions, identity handoff, and Microsoft 365 publication.
The private root reuses existing ingress and platform-owned BYOR/DNS resources by
input rather than creating a gateway or a second copy of shared services.

### 2026-07-28 — fixed starter composition belongs in readable locals
The cross-tenant DNS roots accept only customer facts such as provider resource
IDs, optional existing zone IDs, a DNS label and TTL, and resolver addresses.
Endpoint, zone, record, approval, and forwarding maps are named locals consumed
by `for_each`. Do not make adopters author nested `map(object(...))` schemas for
the fixed DFS, Blob, and SQL composition shown by these starters.

### 2026-07-28 — reusable roots do not ship generated dependency locks
The starter owns provider constraints in each root's `z_versions.tf` but excludes
`.terraform.lock.hcl`. After copying one root, the consumer runs `terraform init`
to generate and review a lockfile for that repository and execution platform. This
supersedes the lockfile wording in the separate-roots decision below; the two
architectures remain fully independent.

### 2026-07-28 — client-selectable Terraform architectures are separate roots
The standard-context and prefixed-backing Private Link DNS designs are
alternatives, not modes in one composition. Each lives in a self-contained
Terraform root with its own provider contract, lockfile, inputs, tfvars,
resources, outputs, README, tests, and state; the parent directory is a catalog
only. Duplicate endpoint and resolver scaffolding intentionally so either root
can be copied for another client without a selector, sibling dependency, or
shared state. Do not recombine them behind an architecture flag.

### 2026-07-28 — validate config selectors before paths and queries
The CD workflow rejects any config selector that is not a lowercase basename of
letters, numbers, and hyphens, then verifies the corresponding tfvars file exists.
This fail-closed gate runs in both plan and apply before the selector reaches a
file path, artifact name, backend key, or JMESPath query.

### 2026-07-28 — compose DNS with AVM; use raw PE only for manual cross-tenant approval
The cross-tenant Private Link DNS example pins Terraform MCP catalog modules for
Private DNS Zone (`0.5.0`) and DNS Resolver (`0.8.0`). The Private Endpoint AVM
`0.2.0` hardcodes `is_manual_connection=false`, so the consumer-side cross-tenant
request uses one documented raw `azurerm_private_endpoint` block with manual
approval while the remaining resources stay on AVM. AVM-managed resources use
`LastAppliedStamp=Disabled` because module blocks cannot express resource-level
`ignore_changes`; static repository/config provenance remains intact.

### 2026-07-16 — AI guidance is portable; central guardrails are structurally read-only
Added an agent-neutral `AGENTS.md`, Terraform path instructions, and a review skill so
standing rules survive client or model changes. The optional MCP reference exposes one
exact eight-tool lookup/validation allowlist backed by an immutable, provenance-stamped
artifact; contract tests fail if a generic or mutation tool appears. AI remains advisory,
and deterministic checks plus people retain merge and apply authority.

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

### A Docker action cannot run on a Container Apps job runner
**Symptom:** the private-runner design used Azure Container Apps jobs, but the PR
workflow invoked Checkov through a Docker action. Container Apps jobs do not support
Docker-in-Docker, so the scan would fail only after an adopter switched from a hosted
runner. **Rule:** preinstall tools in the runner image or install a pinned native CLI;
never use Docker-based actions or Docker commands on this runner class.

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
