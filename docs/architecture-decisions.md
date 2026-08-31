# Architecture decisions

The decisions this repo encodes, each grounded in Microsoft's own guidance. These
were converged by an independent multi-model Azure architecture review for a regulated
(PHI / HIPAA / HITRUST) health-system landing zone. Re-verify every citation against
your own requirements before adopting.

## 1. Build runners — private, ephemeral, explicit ownership boundary

**Decision:** Run private plan/apply jobs on ephemeral runners with network reachability
to the matching environment. Use **self-hosted Container Apps job runners** when the
organization must own the runner image and tools. Use **GitHub-hosted larger runners
with Azure Private Networking** when GitHub should own the runner lifecycle and the
required plan, region, image, and size are available. Both patterns keep untrusted
pull-request jobs away from privileged private dependencies and use protected OIDC
jobs for plan/apply.

- Self-hosted runners reaching private VNet resources, scale-to-zero:
  https://learn.microsoft.com/azure/container-apps/tutorial-ci-cd-runners-jobs
- GitHub-hosted runners with Azure Private Networking:
  https://docs.github.com/en/enterprise-cloud@latest/organizations/managing-organization-settings/configuring-private-networking-for-hosted-compute-products/configuring-private-networking-for-github-hosted-runners-in-your-organization
- Client-agnostic APN Terraform root:
  ../runners/github-hosted-azure-private-networking/

## 2. Remote state — Azure Storage, Entra-auth, private-endpoint only

**Decision:** Terraform state in **Azure Storage**, same tenant/region as resources,
with `use_azuread_auth = true`, **shared-key access disabled**, **public network access
disabled (private endpoint only)**, encryption at rest (CMK if the BAA requires),
**native blob-lease locking**, versioning + soft-delete, **one state file per layer per
environment**. Not a cross-cloud object store (it splits identity, adds egress, and adds
a second compliance boundary to certify).

- Store Terraform state in Azure Storage (state is plain text / sensitive; locking;
  encryption): https://learn.microsoft.com/azure/developer/terraform/store-state-in-azure-storage
- Storage private endpoints: https://learn.microsoft.com/azure/storage/common/storage-private-endpoints
- Authorize blob access with Entra ID + RBAC:
  https://learn.microsoft.com/azure/storage/blobs/authorize-access-azure-active-directory
- Storage encryption / CMK: https://learn.microsoft.com/azure/storage/common/storage-service-encryption

## 3. Local plans — read-only only, no local apply

**Decision:** **No local `apply`, ever.** A read-only local `plan` is acceptable only
from an in-network workstation (e.g. AVD inside the VNet) under the engineer's **own**
least-privilege identity (Reader + Storage Blob Data Reader on state) — never the apply
identity, never a stored key. The pipeline-produced plan artifact is the only plan the
gated apply consumes. The private-endpoint backend physically enforces this off-network.

- WAF: deploy infrastructure changes only through code, through CI/CD; layered IaC
  pipelines: https://learn.microsoft.com/azure/well-architected/operational-excellence/infrastructure-as-code-design

## 4. Pipeline identity — OIDC, least-privilege plan/apply split

**Decision:** **OIDC workload-identity federation**, no secrets on runners. Two
least-privilege identities **per environment**: a **plan** identity (Reader + state
read — cannot mutate) and an **apply** identity (scoped write at the landing-zone
boundary), gated behind a GitHub Environment with required reviewers. Federated
credentials scoped to `repo:ORG/REPO:environment:<env>` so a dev branch cannot mint
production credentials.

- GitHub -> Azure OIDC, federated credentials, no stored secrets:
  https://learn.microsoft.com/azure/developer/github/connect-from-azure-openid-connect
- Workload identity federation: https://learn.microsoft.com/entra/workload-id/workload-identity-federation

## 5. State safety is a gate (OPA)

**Decision:** Two `conftest`/OPA policies hard-fail the pipeline: (a) the backend key
must be nested `<prefix>/<config>.tfstate` (a flat key is the laptop-vs-CD divergence
bug); (b) a plan that deletes/replaces live resources or mass-creates (> 20) is blocked
as the empty/wrong-state rebuild signature, overridable only by a reviewed
`allow_recreate`. See `policy/`.

- IaC misconfiguration scanning as a gate:
  https://learn.microsoft.com/azure/defender-for-cloud/iac-vulnerabilities

## 6. Authoring agent — IDE loop now, managed agent deferred

**Decision:** Keep human Terraform authoring in **VS Code + GitHub Copilot + scoped
MCP**; do PR review / standards enforcement **natively in GitHub** (protected branches,
required checks, CODEOWNERS, policy-as-code). **Defer** a centralized managed agent
until data residency, DLP, private networking, Entra RBAC, audit logging, and BAA scope
are validated. If/when built, target **Azure AI Foundry Agent Service** (VNet-injected,
private endpoints, dedicated per-agent Entra identity, bring-your-own data stores,
content-safety guardrails), **scoped Terraform-only**, as an **advisory reviewer** —
**never the apply approver** (auto-approving infra change in a PHI tenant violates
separation of duties).

- GitHub Copilot + MCP in the IDE:
  https://docs.github.com/copilot/customizing-copilot/extending-copilot-chat-with-mcp
- Azure AI Foundry Agent Service overview:
  https://learn.microsoft.com/azure/ai-foundry/agents/overview
- Foundry Agent private networking / VNet injection / BYO data stores:
  https://learn.microsoft.com/azure/ai-foundry/agents/how-to/virtual-networks

## Compliance posture (applies throughout)

PHI / HIPAA / HITRUST: a BAA is required and must cover every service in the data path;
**HITRUST is NOT inherited** from Azure — you implement and evidence the controls. Map
the pipeline to the Azure Policy HIPAA/HITRUST initiative.

- Azure HIPAA / BAA: https://learn.microsoft.com/azure/compliance/offerings/offering-hipaa-us
- Azure HITRUST (shared responsibility): https://learn.microsoft.com/azure/compliance/offerings/offering-hitrust
- HIPAA/HITRUST Azure Policy initiative: https://learn.microsoft.com/azure/governance/policy/samples/hipaa-hitrust-9-2
