# Azure Landing Zone — Terraform CI/CD Reference

A clean, self-contained starting point for running **Terraform for an Azure Landing
Zone through GitHub Actions**, hardened for a **private-endpoint-only, regulated
(PHI / HIPAA / HITRUST) environment**.

It encodes the decisions an Azure architecture review converged on for a health-system
landing zone, with every pattern grounded in Microsoft's own guidance (Cloud Adoption
Framework, Well-Architected Framework, Azure Verified Modules). Clone it, adapt the
names, and you have a working, opinionated pipeline on day one.

> This is a **reference / starter**, not a turnkey product. Replace the example names,
> review every value against your own security baseline, and validate the Microsoft
> Learn citations in `docs/architecture-decisions.md` before adopting.

## What's in here

| Path | What it is |
|---|---|
| `.github/workflows/terraform-validate.yml` | PR gate: `fmt`, `validate` (backend-free, so a template clone is green), IaC security scan; plus a speculative `plan` + **governance guardrails** when a backend is configured. |
| `.github/workflows/terraform-cd.yml` | Push/dispatch: `plan` → captured artifact → **OPA state-safety + governance gate** → **gated** `apply`. |
| `.github/workflows/terraform-drift-detect.yml` | Scheduled read-only plan that alerts when live infrastructure drifts from the committed Terraform. |
| `.github/workflows/foundry-iq-sync.yml` | Optional: sync this repo's docs + policies to an Azure Blob container so a Foundry IQ knowledge source can ground an agent on them. Inert until configured. |
| `.github/workflows/state-migrate.yml` | One-time, attended migration of a flat/laptop state file to the per-config CD key (Terraform-native, no Azure CLI needed). |
| `.github/workflows/policy-test.yml` | Runs the OPA policy unit tests on every change to `policy/`. |
| `.github/workflows/workflow-lint.yml` | Lints the repo's own GitHub Actions workflows with **actionlint** on every change to `.github/workflows/**` — catches the "valid YAML, invalid to GitHub's compiler" class (bad context refs, empty interpolations, broken `needs`) in PR review, before it reaches `main`. |
| `.github/workflows/llm-council.yml` | Optional **advisory multi-model PR review** — 2-3 distinct LLMs independently review each PR diff and post one consolidated verdict comment (`.github/scripts/llm-council.py`). Defaults to GitHub Models (zero setup), provider-pluggable. Not a merge gate unless you opt in. See `docs/llm-council.md`. |
| `.github/CODEOWNERS` | Required-reviewer governance — the human gate on infra and policy changes. |
| `policy/*.rego` | **State-safety gate** (flat-key + rebuild guards) **and a governance pack** (regions, tags, subscriptions, network, transport). All unit-tested (39 tests). |
| `policy/governance.params.json` | Client-editable config that turns each governance guardrail on/off and scopes it. |
| `infra/` | Minimal Terraform skeleton + `backend.hcl.example` + `configs/<scope>-<region>-<env>.tfvars` naming. |
| `examples/cross-tenant-private-link-dns/` | Catalog of two independent client-agnostic Terraform roots: standard resolution contexts and prefixed backing zones. Each uses readable scalar/list inputs and local resource maps for manual-approval cross-tenant Storage DFS/Blob and Azure SQL Private Endpoints. |
| `examples/foundry-agent-teams/` | Two independent Microsoft Foundry Prompt Agent roots: a public pilot and a Standard/BYO private-network pattern with existing data services, DNS, and a dedicated private MCP subnet. Both stage Foundry first, then Bot Service after agent identity creation. |
| `.github/workflows/foundry-agent-data-plane.yml` | Human-gated OIDC workflow that versions/promotes the checked-in Toolbox, creates the Prompt Agent, emits the Terraform principal-ID handoff, and publishes to Microsoft 365 only after Bot Service apply. |
| `infra/locals.tf` | **Provenance tags** — `DeployedByRepo` (from `github.repository`) on every resource via `local.common_tags`, plus a `LastApplied` stamp the CD job writes post-apply. Lets an agent (or you, weeks later) trace what deployed a resource and when. |
| `runners/README.md` | The **self-hosted, in-VNet, ephemeral runner** pattern (the only way to reach private-endpoint state). |
| `.vscode/mcp.json.example` | Agent config: the Terraform + Azure MCP servers for the VS Code + GitHub Copilot authoring loop. |
| `.github/copilot-instructions.md` | Repo-scoped Copilot guidance so the agent writes Terraform that matches these conventions. |
| `.github/instructions/terraform.instructions.md` | Path-scoped Terraform rules for modules, state, identity, security, and required evidence. |
| `.github/skills/terraform-review/SKILL.md` | Agent-neutral, evidence-first Terraform review procedure that cannot authorize apply. |
| `AGENTS.md` | Shared operating contract for Copilot, Claude Code, Codex, Gemini CLI, and other agents. |
| `examples/read-only-guardrails-mcp/` | Runnable eight-tool MCP reference whose exact read-only contract and immutable artifact are tested in CI. |
| `.github/workflows/read-only-mcp-test.yml` | Contract gate for the read-only MCP allowlist, artifact immutability, and pinned real-SDK load. |
| `DECISIONS.md` | A living, append-only decisions + learned-guardrails log the agent reads **before** choosing, so a decision is made once — not re-litigated each session. |
| `docs/architecture-decisions.md` | The cited decision record (runners, state, local plans, identity, agent platform). |
| `docs/implementation-playbook.md` | Engineering adoption sequence with commands, file links, exit evidence, rollback, and preview/entitlement gates. |
| `docs/policy-guardrails.md` | What each OPA policy checks, how to configure it, and how to add your own. |
| `docs/foundry-iq.md` | How to ground an AI agent on this repo via a Foundry IQ knowledge base (repo → blob → knowledge source → agent). |
| `docs/llm-council.md` | The advisory multi-model PR-review council: how it works, provider config (GitHub Models / Azure OpenAI / OpenAI / Anthropic), advisory→required-gate promotion, and the data-governance note for regulated repos. |
| `docs/state-migration-runbook.md` | Step-by-step for the flat → per-config state migration. |

## The decisions this repo encodes (one-liners — full rationale + citations in `docs/`)

1. **Runners: self-hosted, in-VNet, ephemeral.** Once state / Key Vault / storage are
   private-endpoint-only, GitHub-hosted runners cannot reach them. Container Apps jobs
   with scale-to-zero are the cleanest fit.
2. **Remote state: Azure Storage, Entra-auth, no keys, private-endpoint only**, with
   versioning + native blob-lease locking, one state file **per layer per environment**.
   Not a cross-cloud object store.
3. **Local plans: read-only only, from an in-network workstation, under your own
   least-privilege identity. No local `apply`, ever** — all authoritative plan + apply
   run in the pipeline (the private-endpoint backend enforces this off-network).
4. **Identity: OIDC workload-identity federation, no secrets.** Two least-privilege
   identities per environment: a **plan** identity (Reader + state read) and an
   **apply** identity (scoped write), gated behind a GitHub Environment with approvals.
5. **State safety is a gate, not a hope.** Two OPA policies hard-fail the pipeline if
   the backend key is flat or the plan looks like an empty-state rebuild.
6. **Authoring: VS Code + GitHub Copilot + scoped MCP now; PR review native in GitHub.**
   A centralized managed agent (Azure AI Foundry Agent Service, VNet-injected, scoped
   Terraform-only, **advisory not approver**) is a deferred follow-on, after the
   compliance boundary is proven.
7. **Provenance is a tag, not a memory.** Every resource carries `DeployedByRepo`
   (from `github.repository`) and a post-apply `LastApplied` stamp, so an agent — or a
   human weeks later — can answer "what deployed this, and when?" off the resource
   itself, with no state access. `LastApplied` is stamped by CI and excluded from the
   plan via `ignore_changes`, so it never churns a diff.
8. **AI review is advisory, multi-model, and a second opinion — never the gate.** An
   optional "LLM council" has 2-3 *distinct* models independently review each PR and post
   one consolidated verdict, alongside `CODEOWNERS` (the human gate). It defaults to
   off-critical-path advisory and only becomes a required check if you opt in. Multi-model
   avoids single-model blind spots; advisory avoids handing merge authority to a model.
   See `docs/llm-council.md`.

## Quick start

```bash
# 1. Create the remote-state storage account (Entra-auth, private endpoint) out of band.
# 2. Render your backend config:
cp infra/backend.hcl.example infra/backend.hcl   # then fill in your values
# 3. Name your first config (env suffix LAST so *-prd.tfvars globs across regions):
cp infra/configs/example-eus-dev.tfvars infra/configs/<scope>-<region>-<env>.tfvars
# 4. Configure GitHub Environments (<env> + <env>-apply) with OIDC federated identities.
# 5. Open a PR — terraform-validate runs. Merge — terraform-cd plans, gates, applies.
```

See `docs/architecture-decisions.md` for the why, and `runners/README.md` for the
self-hosted runner setup that makes private-endpoint state reachable.
Use `docs/implementation-playbook.md` for the phase-by-phase build and validation
sequence, including the tested read-only MCP and agent-review examples.

## Provenance

The CI/CD shape, the OPA state-safety policies, and the state-migration runbook are
generalized from a production Azure Terraform fleet. Customer, tenant, and
resource-specific identifiers have been stripped — every value here is a placeholder.
