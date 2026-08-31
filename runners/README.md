# Private, ephemeral runners

Once the landing zone is hardened to **private-endpoint-only** (Terraform state,
Key Vault, and storage reachable only from inside the VNet), the runner must receive
private network reachability. This repository supports two patterns: self-hosted
Container Apps job runners inside the VNet, and GitHub-hosted larger runners attached
to a delegated Azure subnet through Azure Private Networking (APN).

Choose the ownership boundary deliberately. Self-hosting gives the organization direct
control of the image and runtime. APN transfers runner lifecycle and base-image
operations to GitHub while keeping network policy, routing, private dependencies, and
Azure authorization inside the customer boundary.

## Option 1: Azure Container Apps jobs (self-hosted, scale-to-zero)

Microsoft's own tutorial shows a self-hosted GitHub Actions runner as a Container Apps
**job** that runs inside the job's virtual network — exactly the private-endpoint
reachability you need — and scales to zero when idle (you pay only while a job runs):

  https://learn.microsoft.com/azure/container-apps/tutorial-ci-cd-runners-jobs

Why ephemeral container jobs:

- **Reachability:** the job runs in a VNet-integrated Container Apps environment, so it
  can resolve and reach the private endpoints for state / Key Vault / storage.
- **Clean isolation:** a fresh, hardened container per job — no persistent host to
  harbor secrets or PHI-adjacent state between runs.
- **Cost:** scale-to-zero means no idle runner fleet.
- **Compliance:** you own and patch the runner image (a HITRUST control you implement),
  and a malicious PR cannot persist inside the VNet.

## Wiring

1. Build a hardened runner image (pinned Terraform, conftest, minimal base; scan it).
2. Deploy a VNet-integrated Container Apps environment in a dedicated CI/CD subnet that
   can reach the state/KV/storage private endpoints (verify private DNS resolution).
3. Register the runner to your repo/org with a least-privilege runner group.
4. Set the repo/Environment variable `RUNNER_LABELS` to your runner's label set, e.g.
   `["self-hosted","alz-runner","linux","x64"]`. The workflows read it; absent, they
   fall back to `ubuntu-latest` (only valid while state is still publicly reachable).

Container Apps jobs do **not** support running Docker commands inside the runner
container. Preinstall required tools in the hardened image or use pinned native
installers in the workflow. Do not use Docker-based actions for Checkov, conftest,
or other required gates; `terraform-validate.yml` installs pinned Checkov as a
Python CLI for this reason.

## Option 2: GitHub-hosted larger runners with Azure Private Networking

Use the standalone
[`github-hosted-azure-private-networking/`](github-hosted-azure-private-networking/)
Terraform root when GitHub-hosted larger runners are available and GitHub should own
runner provisioning, patching, and teardown. The root creates one environment-specific
runner VNet, one subnet delegated to `GitHub.Network/networkSettings`, one separate
nondelegated dependency subnet, Azure NetworkSettings, a restricted runner group, and
a GitHub-hosted runner pool.

The root is copied once per real environment and state boundary. It requires an
existing resource group, route table, egress policy, private endpoints, DNS, OIDC
identities, role assignments, protected GitHub environment, and monitoring controls.
It does not create those shared or workload-owned dependencies.

APN assigns each ephemeral runner a dynamic address from the delegated subnet. It is
not Azure Private Link. Private Endpoints remain target-side resources in the separate
dependency subnet. Network reachability and Azure authorization must both be granted
for each approved data-plane operation; the opposite environment and all undeclared
dependencies remain denied.

Use standard GitHub-hosted runners without an Azure token for untrusted pull-request
checks. Reserve the APN runner group for protected workflows selected by repository and
fully qualified workflow reference. A live job can use every route and token available
to it, so ephemerality does not replace workflow isolation, conditioned OIDC, narrow
RBAC, immutable artifacts, independent production approval, or active alerting.

## Alternatives

- **VM scale set runners** — simpler if you already operate VMSS; less elastic, you own
  more host lifecycle.

## Hard rules

- Ephemeral / clean-job isolation, outbound-only egress, explicit inbound denial,
  least-privilege runner groups, conditioned OIDC, and centralized logs.
- For self-hosted jobs, harden and patch the image and make no Docker-in-Docker
  assumptions. For APN, validate the selected GitHub or governed custom image and do
  not apply TLS interception to a default image.
- Validate the complete workflow against the actual runner image and private network
  path before private-state cutover.
- The runner identity is the pipeline's OIDC identity — keep plan read-only and apply
  scoped-write (see docs/architecture-decisions.md, Identity).
