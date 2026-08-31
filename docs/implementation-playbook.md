# Governed Terraform and AI-assisted review implementation playbook

This playbook turns the repository's architecture decisions into an executable,
evidence-producing adoption sequence. It keeps one authority model throughout:

1. deterministic checks enforce machine-verifiable controls;
2. people approve merge and apply;
3. AI services provide advisory authoring, context, and review;
4. Git stores the canonical, reviewed standard.

The phases are intentionally separable. Do not make an AI or preview service a
dependency of Terraform delivery. A phase advances only when its exit evidence
is recorded and its rollback has been exercised.

## Implementation map

| Capability | Executable reference |
|---|---|
| Cross-agent operating contract | [`AGENTS.md`](../AGENTS.md) |
| Repository-wide Copilot rules | [`.github/copilot-instructions.md`](../.github/copilot-instructions.md) |
| Terraform path rules | [`.github/instructions/terraform.instructions.md`](../.github/instructions/terraform.instructions.md) |
| Terraform review procedure | [`.github/skills/terraform-review/SKILL.md`](../.github/skills/terraform-review/SKILL.md) |
| PR validation | [`.github/workflows/terraform-validate.yml`](../.github/workflows/terraform-validate.yml) |
| Plan and gated apply | [`.github/workflows/terraform-cd.yml`](../.github/workflows/terraform-cd.yml) |
| One-time state migration | [`.github/workflows/state-migrate.yml`](../.github/workflows/state-migrate.yml) |
| Policy tests | [`.github/workflows/policy-test.yml`](../.github/workflows/policy-test.yml) |
| Workflow compiler checks | [`.github/workflows/workflow-lint.yml`](../.github/workflows/workflow-lint.yml) |
| Read-only MCP server | [`examples/read-only-guardrails-mcp/server.py`](../examples/read-only-guardrails-mcp/server.py) |
| Read-only MCP release fixture | [`examples/read-only-guardrails-mcp/guardrails.json`](../examples/read-only-guardrails-mcp/guardrails.json) |
| MCP contract tests | [`examples/read-only-guardrails-mcp/tests/test_contract.py`](../examples/read-only-guardrails-mcp/tests/test_contract.py) |
| MCP CI contract | [`.github/workflows/read-only-mcp-test.yml`](../.github/workflows/read-only-mcp-test.yml) |
| Optional multi-model review | [`.github/workflows/llm-council.yml`](../.github/workflows/llm-council.yml) |
| Council implementation and controls | [`docs/llm-council.md`](llm-council.md) |
| Private runner decision guide | [`runners/README.md`](../runners/README.md) |
| GitHub-hosted APN runner template | [`runners/github-hosted-azure-private-networking/`](../runners/github-hosted-azure-private-networking/) |

## Phase 0 - Establish deterministic delivery

### 0.1 Create the repository governance boundary

Configure the default branch to require pull requests, required checks,
conversation resolution, and reviews from [`.github/CODEOWNERS`](../.github/CODEOWNERS).
Create one GitHub Environment per apply boundary, such as `dev-apply` and
`prd-apply`, and require accountable human reviewers for production.

Set nonsecret repository variables. Use the actual config names and Azure IDs:

```bash
gh variable set RUNNER_LABELS --body '["self-hosted","linux","x64","in-vnet"]'
gh variable set AZURE_TENANT_ID --body '<tenant-guid>'
gh variable set AZURE_SUBSCRIPTION_ID --body '<subscription-guid>'
gh variable set AZURE_PLAN_CLIENT_ID --body '<plan-app-client-guid>'
gh variable set AZURE_APPLY_CLIENT_ID --body '<apply-app-client-guid>'
gh variable set TF_BACKEND_RESOURCE_GROUP --body '<state-resource-group>'
gh variable set TF_BACKEND_STORAGE_ACCOUNT --body '<state-storage-account>'
gh variable set TF_BACKEND_CONTAINER --body '<state-container>'
gh variable set TF_BACKEND_KEY_PREFIX --body '<landing-zone-layer>'
```

Do not store Azure client secrets, storage keys, or SAS tokens. Federated
credentials must be constrained to the repository and the intended environment.
Give the plan principal only the read permissions required for Azure and state;
give the apply principal only the write scope required by the target layer.

For self-hosted Container Apps job runners, build Terraform, Python, and other common
tools into the hardened image or install pinned native packages. Container Apps jobs
cannot run Docker commands inside the runner container, so the starter deliberately
runs Checkov as a pinned Python CLI instead of a Docker action.

### 0.2 Select the private runner ownership model

Use the [runner decision guide](../runners/README.md) to select one private execution
pattern. Do not combine both patterns into one Terraform state merely to preserve an
option.

For self-hosted execution, deploy the Container Apps job runner through its own
environment stack, register it in a restricted runner group, and validate the hardened
image and private DNS path.

For GitHub-hosted execution, copy the
[APN runner root](../runners/github-hosted-azure-private-networking/) once per real
environment. Provide the existing environment resource group and route table, runner
and dependency CIDRs, organization database ID, repository and workflow IDs, approved
image and size, concurrency ceiling, and only the private dependency endpoints justified
by named workflow operations. Keep the dependency map empty until the network path,
data-plane role, owner, positive test, and negative test are approved together.

Run the root's formatting, backend-free initialization, validation, Terraform mock
tests, PowerShell REST-bridge contract tests, and fail-closed Checkov scan. Then inspect
a protected pipeline plan. The template is complete without a backend or live apply;
the consuming environment stack owns state and deployment.

**Exit evidence:** selected ownership model, runner entitlement and region, subnet
capacity including GitHub's 30 percent buffer, private DNS and route evidence, selected
repositories and workflows, conditioned OIDC subjects, least-privilege roles, green
source tests, and one allowed plus one denied scheduling/network test.

**Rollback:** stop scheduling the group and revoke its OIDC trusts first. For APN,
destroy only the environment root after reviewing the plan and preserving audit/network
evidence. Do not delete shared route tables, Firewall policy, DNS, Private Endpoints,
backends, identities, or log destinations from the runner state.

### 0.3 Configure private state without creating a second state scheme

Copy [`infra/backend.hcl.example`](../infra/backend.hcl.example) locally and use
one nested key per config:

```hcl
key                = "platform/core-eus-prd.tfstate"
use_azuread_auth   = true
use_oidc           = true
```

Do not select a Terraform workspace. If a live stack currently uses a flat key,
run the attended [`state-migrate.yml`](../.github/workflows/state-migrate.yml)
workflow before the first CD plan. Confirm the source and destination blobs,
state serial, lineage, resource count, and a zero-change plan after migration.

### 0.4 Prove the baseline locally and in a pull request

```bash
terraform -chdir=infra fmt -check -recursive
terraform -chdir=infra init -backend=false -input=false
terraform -chdir=infra validate
opa test policy/ -v
```

Open a pull request and require `terraform-validate`, `policy-test`, and
`workflow-lint`. When the backend variables are configured, inspect the
speculative plan and OPA result. Then deliberately violate one enabled policy in
a disposable branch and capture the failed check as evidence that policy blocks
without help from an AI service.

**Exit evidence:** branch rules, environment reviewers, federated-credential
subjects, scoped role assignments, state protections, successful baseline runs,
and one intentional policy failure.

**Rollback:** disable the new workflows and restore the prior branch-rule export.
Do not migrate or delete state as a rollback shortcut.

## Phase 1 - Add Git-native agent guidance

### 1.1 Adopt the four guidance layers

Copy and tailor these reviewed files:

- [`AGENTS.md`](../AGENTS.md) for rules every coding agent must follow;
- [repository instructions](../.github/copilot-instructions.md) for universal
  Copilot context;
- [Terraform path instructions](../.github/instructions/terraform.instructions.md)
  for rules that should load only beside Terraform files;
- [the Terraform review skill](../.github/skills/terraform-review/SKILL.md) for
  an explicit, reusable review procedure.

Keep customer identifiers, secrets, IP ranges, state values, and PHI out of all
four files. The shared contract must not assume one model vendor, client, tool
prefix, transcript format, or local configuration directory.

### 1.2 Validate behavior with controlled pull requests

Create two small, nonproduction pull requests:

1. A compliant naming/tag change. The review should cite the relevant files,
   explain the plan, and report no fabricated blockers.
2. A deliberately noncompliant change containing a flat backend key, workspace
   selection, or standing secret. Deterministic checks must fail, and the AI
   review should independently identify the same defect.

Confirm the reviewer uses instructions from the protected base branch. Record
the review comments, false positives, missed controls, runtime, and human effort.

**Exit evidence:** both pull requests, deterministic results, AI review output,
and a short scorecard of correct findings, misses, and noise.

**Rollback:** revert the customization commit. Deterministic workflows and human
approval remain unchanged.

## Phase 2 - Prove a structurally read-only MCP contract

### 2.1 Run the reference implementation

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install -r examples/read-only-guardrails-mcp/requirements.txt
python -m unittest discover -s examples/read-only-guardrails-mcp/tests -v
python examples/read-only-guardrails-mcp/server.py
```

The reference exposes exactly eight lookup or validation tools. It has no
generic HTTP, URL, shell, file-write, GitHub-write, secret, ARM-mutation, or
Terraform-execution tool. The tests parse the decorated server functions,
compare them with the exact allowlist, invoke every tool, and prove the approved
artifact remains byte-for-byte unchanged.

### 2.2 Replace the fixture through a release pipeline

Do not edit the running service. In the governance repository:

1. review standards through a normal pull request;
2. build a compact artifact from the approved commit;
3. stamp `release`, `source_commit`, `schema_version`, and classification;
4. scan the artifact for disallowed data and sign or attest the build;
5. deploy the immutable artifact and record its SHA-256 hash;
6. retain the prior tagged artifact for rollback.

The sample's `guardrails_manifest_get` response demonstrates the provenance
shape. Replace the sanitized fixture's placeholder source commit before any
pilot claim.

### 2.3 Test the negative boundary

Add a temporary decorated mutation tool on a disposable branch and confirm
`read-only-mcp-test` fails. Also test malformed identifiers, unknown controls,
an absent artifact, an unavailable server, and a prior-release rollback. A
missing or crashed contract test is a block, never a silent pass.

**Exit evidence:** exact tools/list capture, green six-test contract, real-SDK
load, artifact hash, negative mutation test, and successful prior-release rollback.

**Rollback:** redeploy the preceding tagged artifact or remove the MCP client
configuration. Git-native instructions continue to carry the baseline rules.

## Phase 3 - Deploy a sanitized nonproduction MCP host

Use the official Azure Functions Streamable HTTP MCP pattern only after the local
contract is green. Treat Flex Consumption MCP hosting as preview: isolate it from
production delivery and keep it nonblocking.

Required implementation controls:

- managed identity and no local deployment secret;
- TLS, private endpoint, private DNS, and restricted egress for sensitive content;
- reader-only data-plane authorization with no mutation role;
- immutable package deployment from the reviewed release artifact;
- structured telemetry containing release ID, tool name, status, latency, and
  correlation ID, but not tool arguments, responses, plans, or state fragments;
- budget, availability, cold-start, p95 latency, auth-failure, and unknown-tool alerts.

Use [`runners/README.md`](../runners/README.md) for the ephemeral in-VNet client
pattern. Validate DNS and TLS from that runner, not from a public workstation.

**Exit evidence:** sanitized-data approval, identity role export, private DNS
resolution, successful allowlisted calls, denied mutation attempts, redacted
telemetry, measured latency, and one release rollback.

**Rollback:** remove the client registration and redeploy the prior artifact.
Do not weaken networking or grant write access to recover service.

## Phase 4 - Integrate native Copilot code review

Enable Copilot code review for a nonproduction repository and configure the
approved MCP client to reach the sanitized service. GitHub's current remote code
review client does not support OAuth-authenticated remote MCP servers, so the
production-oriented pattern is an OIDC-authenticated local bridge on the
ephemeral in-VNet runner. A rotating function key is only a time-bounded sandbox
fallback for formally sanitized content.

For each test pull request, capture:

- base-branch instruction and skill version;
- MCP release, artifact hash, and exact invoked tools;
- deterministic check results;
- review findings, false positives, misses, and elapsed time;
- human disposition of each finding.

Run an outage drill by disabling the MCP client. Review quality may lose central
context, but Terraform validation, policy gates, CODEOWNERS, and apply approval
must continue unchanged.

**Exit evidence:** session/audit record showing only allowlisted tools, two
representative reviews, outage drill, and security-owner approval.

**Rollback:** remove the MCP client configuration and retain Git-native review.

## Phase 5 - Validate the optional multi-model workflow

The [multi-model council](llm-council.md) is a portability demonstration and
advisory second opinion, not an architecture success criterion.

Before enabling the default GitHub Models provider:

1. confirm an enterprise owner has enabled or delegated GitHub Models;
2. confirm the organization and repository expose the Models policy surface;
3. verify current identifiers for two or three approved, distinct publishers;
4. approve data-processing terms, budget, and repository classification;
5. open a same-repository, non-draft pull request with a small reviewable diff.

A green fail-soft job is not a successful smoke test. Require genuine independent
model findings, one consolidated comment, and clean authorization logs. If the
organization does not expose GitHub Models, record the feature as unavailable
and continue with native Copilot, deterministic checks, and human review.

**Exit evidence:** entitlement approval, model IDs and publishers, per-model
responses, consolidated comment, cost record, and failure-mode test.

**Rollback:** disable the workflow or leave it advisory. Never relax primary
checks to compensate for an unavailable model provider.

## Phase 6 - Production hardening and promotion

Run at least two nonproduction changes and one failure drill through the complete
flow. Define promotion thresholds before measuring them:

- zero unauthorized tool exposure or write-capable identity;
- zero PHI, secret, or state-value leakage;
- all deterministic failures still block;
- acceptable review precision, recall sample, latency, availability, and cost;
- successful prior-release rollback within the approved objective;
- named owners for policy, artifact release, runtime, security monitoring, and
  incident response.

Complete threat modeling, data-flow and retention review, BAA/service-scope
validation, incident runbooks, disaster recovery, private-network evidence, and
formal risk acceptance for every preview feature. Promote each optional layer
independently; do not promote the entire stack as one indivisible control.

## Research and review are separate capabilities

Microsoft 365 Researcher can be available interactively while still lacking a
supported headless agent identifier for automation. Do not automate its UI or
claim API access from UI visibility. For repeatable engineering research, use an
approved callable internal-search API or an organization-owned research service;
keep confidential material out of public web grounding and validate citations
before they affect a design decision. Research output remains advisory and is
never a merge or apply credential.

## Evidence package template

Store the following with the pilot decision record:

```text
release_id:
source_commit:
artifact_sha256:
repository_commit:
terraform_config:
backend_key:
plan_identity:
apply_identity:
deterministic_checks:
ai_review_layers:
mcp_tools_invoked:
data_classification:
exceptions:
human_approvers:
rollback_result:
residual_risks:
```

## Authoritative references

- Azure landing zones: https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/
- Infrastructure as code design: https://learn.microsoft.com/azure/well-architected/operational-excellence/infrastructure-as-code-design
- Terraform state in Azure Storage: https://learn.microsoft.com/azure/developer/terraform/store-state-in-azure-storage
- GitHub to Azure OIDC: https://learn.microsoft.com/azure/developer/github/connect-from-azure-openid-connect
- Ephemeral Container Apps job runners: https://learn.microsoft.com/azure/container-apps/tutorial-ci-cd-runners-jobs
- Azure Functions MCP servers: https://learn.microsoft.com/azure/azure-functions/self-hosted-mcp-servers
- GitHub Copilot code review: https://docs.github.com/en/copilot/concepts/agents/code-review
- Configure MCP for Copilot code review: https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/configure-mcp-servers
- Copilot custom instructions: https://docs.github.com/en/copilot/tutorials/use-custom-instructions
- GitHub Models governance: https://docs.github.com/en/github-models/github-models-at-scale/manage-models-at-scale
