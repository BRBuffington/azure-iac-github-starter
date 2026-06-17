# Self-hosted, in-VNet, ephemeral runners

Once the landing zone is hardened to **private-endpoint-only** (Terraform state,
Key Vault, and storage reachable only from inside the VNet), **GitHub-hosted runners
cannot reach your state account** — they are GitHub-managed VMs outside your network.
The pipeline must run on **self-hosted runners placed inside the VNet**.

## Recommended: Azure Container Apps jobs (ephemeral, scale-to-zero)

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

## Alternatives

- **VM scale set runners** — simpler if you already operate VMSS; less elastic, you own
  more host lifecycle.
- **VNet-injected GitHub-hosted larger runners** — offloads patching to GitHub, at the
  cost of runner-image control (weaker "we implement the control" story for HITRUST).

## Hard rules

- Ephemeral / clean-job isolation, hardened + patched image, outbound-only egress, no
  inbound management ports, least-privilege runner group, centralized logs.
- The runner identity is the pipeline's OIDC identity — keep plan read-only and apply
  scoped-write (see docs/architecture-decisions.md, Identity).
