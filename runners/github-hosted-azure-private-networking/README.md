# GitHub-hosted runners with Azure Private Networking

This standalone Terraform root creates one environment-specific GitHub-hosted
larger runner pool attached to an Azure virtual network through Azure Private
Networking (APN).

> Status: generic reference template. It has been formatted, initialized without
> a backend, validated, security-scanned, and tested with mock providers. It has
> not been applied to Azure or GitHub.

Copy this directory as one independent root per environment. Give each copy its
own Azure subscription, backend key, runner VNet, GitHub network configuration,
runner group, workload identities, and protected GitHub environment. Do not put
nonproduction and production in one state or select between them at runtime.

## What this root manages

| Plane | Managed resource or operation |
|---|---|
| Azure subscription | Registration of `GitHub.Network` |
| Azure network | Two Azure Verified Module NSGs and one AVM VNet |
| Runner subnet | Dedicated subnet delegated to `GitHub.Network/networkSettings`, with Azure default outbound access disabled |
| Dependency subnet | Separate nondelegated subnet for approved Private Endpoints, with PE network policies enabled |
| Azure APN | `GitHub.Network/networkSettings@2024-04-02` through AzAPI |
| GitHub access | Selected-repository, selected-workflow runner group with public repositories denied |
| GitHub APN association | Idempotent REST bridge for the hosted-compute network configuration and runner-group binding |
| GitHub compute | GitHub-hosted larger runner pool with a concurrency ceiling and no static public IP |

The default private-dependency rule map is empty. The dependency NSG denies all
inbound traffic until `approved_private_dependencies` names exact destination
prefixes and ports. Its allows are source-scoped to the delegated runner subnet.

This root does not create a resource group, route table, Firewall policy, Private
Endpoint, private DNS zone, Terraform backend, workload identity, Azure role
assignment, GitHub environment, branch protection rule, log destination, or alert.
Those remain in their owning platform stacks. Supplying an ID here does not grant
authorization or prove that the referenced control is correctly configured.

## Architecture boundary

APN is not Azure Private Link. GitHub creates an ephemeral runner NIC with a
dynamic address in the delegated subnet. Private Endpoints are separate target-side
resources in the nondelegated dependency subnet.

Use standard GitHub-hosted runners with no Azure token for untrusted pull-request
tests. Reserve this APN pool for protected jobs that need an approved private
dependency or a scoped Azure management-plane operation. A live job can use every
route and token available to it; ephemerality limits persistence after the job but
does not remove that live-job exposure.

Public egress must follow the supplied route table to an FQDN-aware control such as
Azure Firewall. Allow only the required GitHub domains, Microsoft Entra ID, Azure
Resource Manager, and approved package sources. Reconcile GitHub destinations
against https://api.github.com/meta on an owned schedule. Do not use static GitHub
IP lists as the primary control. Default runner images do not trust an enterprise
TLS-interception CA; use a governed custom image if interception is mandatory.

For private data planes, add both network reachability and least-privilege Azure
authorization. A general Terraform deployment runner normally needs its own state
Blob endpoint and container-scoped state role. An image-publishing workflow normally
needs the matching private container registry endpoints and a repository-scoped
writer where supported. Key Vault, SQL, on-premises, the opposite environment, and
other endpoints remain denied until a named workflow operation justifies them.

## Prerequisites

1. Confirm GitHub plan entitlement, organization ownership, region support, data
   residency, larger-runner quota, and the requested machine image and size.
2. Provide an existing resource group and a route table in the same environment
   subscription. The route table must send Internet traffic to the approved egress
   control. If policy requires Private Endpoint inspection, configure PE network
   policies and effective specific routes; a `0.0.0.0/0` route does not override a
   Private Endpoint route by itself.
3. Create approved Private Endpoints and private DNS in their owning stacks. Record
   their exact addresses before populating `approved_private_dependencies`.
4. Give the Azure apply identity the scoped rights required to register
   `GitHub.Network` and manage the resources in this root. Keep plan read-only and
   apply behind an independently approved GitHub environment.
5. Use a fine-grained GitHub token or GitHub App installation token authorized for
   the target organization with these organization permissions:
   - `Administration: write` for the GitHub-hosted runner pool.
   - `Network configurations: write` for APN network configuration CRUD.
   - `Self-hosted runners: write` for the runner-group API, which is shared by
     self-hosted and GitHub-hosted larger runners.
6. Store that token as a protected environment secret. Map it to both `GITHUB_TOKEN`
   for the Terraform GitHub provider and `GH_TOKEN` for the REST bridge. The token is
   inherited by the process and is never a Terraform variable, output, or state value.

## Discover GitHub input IDs

Use an organization owner identity and the same API version as the bridge:

```bash
ORG=example-org

gh api graphql \
  -f login="$ORG" \
  -f query='query($login:String!){organization(login:$login){databaseId}}' \
  --jq '.data.organization.databaseId'

gh api -H 'X-GitHub-Api-Version: 2026-03-10' \
  "/orgs/$ORG/actions/hosted-runners/images/github-owned" \
  --jq '.images[] | [.id,.display_name,.platform] | @tsv'

gh api -H 'X-GitHub-Api-Version: 2026-03-10' \
  "/orgs/$ORG/actions/hosted-runners/machine-sizes" \
  --jq '.machine_specs[] | [.id,.cpu_cores,.memory_gb,.storage_gb] | @tsv'

gh api -H 'X-GitHub-Api-Version: 2026-03-10' \
  "/repos/$ORG/example-repo" --jq '.id'
```

Use the organization `databaseId` as `github_organization_database_id`. Runner
image IDs, sizes, and repository IDs are organization-specific API values; do not
copy the placeholders from `terraform.tfvars.example` into a real plan.

## Configure one environment

1. Copy this root into the environment's deployment repository.
2. Copy `terraform.tfvars.example` to a config file named
   `<scope>-<region>-<env>.tfvars` and replace every placeholder.
3. Set `selected_repository_ids` and fully qualified `selected_workflows`. Every
   workflow entry requires `ORG/REPO/.github/workflows/FILE@REF`.
4. Set `maximum_runners`, then size the delegated subnet for that concurrency plus
   GitHub's 30 percent address buffer and Azure's five reserved addresses. The root
   rejects an undersized subnet.
5. Keep `approved_private_dependencies = {}` until each destination has an approved
   workflow data-plane operation, exact Private Endpoint address, port, Azure role,
   owner, and negative access test.
6. Configure the consuming repository's normal remote backend. Use one nested backend
   key per environment and do not combine per-config keys with Terraform workspaces.
7. Run validation, then obtain a reviewed pipeline plan. Apply only through the
   protected deployment workflow; never run local `terraform apply`.

Example protected-job environment mapping:

```yaml
jobs:
  deploy-production:
    environment: prd
    runs-on: ghr-example-eus-prd
    permissions:
      contents: read
      id-token: write
```

Protect the workflow file with `CODEOWNERS`, use a static branch-to-environment map,
prevent self-review, and disable administrator bypass. Pin third-party actions to full
commit SHAs in consuming workflows. Give `id-token: write` only to the protected job
that exchanges its conditioned OIDC assertion for the matching environment identity.

## Why the REST bridge exists

The pinned `integrations/github` provider manages the runner group and hosted runner,
but version `6.13.0` does not expose hosted-compute network configurations or the
runner group's `network_configuration_id`. `scripts/sync-github-network.ps1` owns only
that missing association through GitHub REST API version `2026-03-10`.

The bridge:

- lists every network configuration and selects one exact name;
- creates or updates one `compute_service=actions` configuration with one Azure
  NetworkSettings ID;
- reads the runner group and patches its required `name` plus the network configuration
  ID only when the binding differs;
- treats an identical repeat as a no-op;
- on Terraform destroy, verifies ownership, detaches with
  `network_configuration_id: null`, then deletes the network configuration; and
- fails closed on duplicate names, ownership drift, an unexpected compute service,
  a missing token, an API error, or a 30-second request timeout.

Terraform creates the hosted runner only after the association succeeds. On destroy,
the hosted runner is removed before the bridge detaches the group and before Azure
deletes NetworkSettings.

## Validate the template

These commands make no Azure or GitHub changes:

```bash
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate -no-color
terraform test -no-color
pwsh -NoLogo -NoProfile -NonInteractive -File tests/sync-github-network.tests.ps1
```

The repository CI also runs the fail-closed Checkov wrapper. Do not commit the local
`.terraform` directory, generated plan files, or this reusable root's generated
`.terraform.lock.hcl`; generate and review a lock file after copying the root into its
long-lived deployment repository.

## Go-live evidence

Hold production until all of these are demonstrated in nonproduction:

| Test | Positive evidence | Negative evidence |
|---|---|---|
| Scheduling | An allowed protected workflow schedules the named pool | An unlisted repository and workflow cannot schedule it |
| Inbound | GitHub provisions and removes an ephemeral runner | Internet and peered-network probes to the runner fail and log the deny |
| Public egress | Required GitHub, Entra, ARM, and approved package operations succeed | An unapproved domain is blocked and logged |
| Private state | Backend DNS resolves privately; init, read/write, lease locking, and recovery succeed | The opposite environment's state and unrelated containers fail |
| Private registry | Registry and regional data endpoints resolve privately; image push succeeds | Unrelated registries and repositories fail |
| Azure identity | The protected job gets only its environment token and completes the frozen command list | Role assignment, identity creation, network mutation, secret listing, and unrelated deletes fail unless explicitly approved |
| Containment | Disabling the runner group and OIDC trust stops new privileged work | Revoked jobs cannot reuse a token or cross an environment boundary |
| Evidence | GitHub audit, Entra, Azure Activity, VNet flow, Firewall, dependency, and Defender signals reach named owners | Audit-stream gaps and unexpected state, route, RBAC, or public-access changes alert |

## Rollback and teardown

Stop scheduling first, revoke the environment's OIDC trusts, and preserve logs and
state evidence. Run destroy only from the protected pipeline after confirming the
plan removes this root's runner pool, network configuration, Azure NetworkSettings,
VNet, and NSGs. The bridge refuses to delete a same-named network configuration if it
no longer references this state's NetworkSettings ID.

This root also owns the subscription's `GitHub.Network` provider registration, so its
destroy unregisters that provider. If the subscription contains another APN deployment,
move registration ownership to the shared subscription bootstrap before adopting this
root. Do not destroy shared route tables, Firewall policy, DNS, Private Endpoints,
backends, identities, or log destinations from this state.

## Authoritative references

- GitHub APN configuration:
  https://docs.github.com/en/enterprise-cloud@latest/organizations/managing-organization-settings/configuring-private-networking-for-hosted-compute-products/configuring-private-networking-for-github-hosted-runners-in-your-organization
- GitHub hosted-compute network configuration REST API:
  https://docs.github.com/en/rest/orgs/network-configurations?apiVersion=2026-03-10
- GitHub runner-group REST API:
  https://docs.github.com/en/rest/actions/self-hosted-runner-groups?apiVersion=2026-03-10
- GitHub-hosted runner REST API:
  https://docs.github.com/en/rest/actions/hosted-runners?apiVersion=2026-03-10
- GitHub OIDC with Azure:
  https://docs.github.com/en/actions/how-tos/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-azure
- Azure NetworkSettings template reference:
  https://learn.microsoft.com/azure/templates/github.network/networksettings
- Azure subnet delegation:
  https://learn.microsoft.com/azure/virtual-network/subnet-delegation-overview
- Azure Private Endpoint route and NSG policy:
  https://learn.microsoft.com/azure/private-link/disable-private-endpoint-network-policy
- Inspect Private Endpoint traffic with Azure Firewall:
  https://learn.microsoft.com/azure/private-link/inspect-traffic-with-azure-firewall
- Azure Storage private endpoints:
  https://learn.microsoft.com/azure/storage/common/storage-private-endpoints
- Azure Container Registry private endpoints:
  https://learn.microsoft.com/azure/container-registry/container-registry-private-endpoints
