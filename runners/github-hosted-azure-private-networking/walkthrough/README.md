# Existing-resource APN walkthrough

A small, attended PowerShell setup sequence adapted from
[Matt Allford's github-preparation.ps1](https://github.com/mattallford/github-hosted-runner-azure-networking/blob/5dd2c4847fc1275a84369ed4d39a9043db6d2f06/github-preparation.ps1)
and his [video](https://www.youtube.com/watch?v=8xYz_oCQQsg&t=2202s).
Azure and GitHub documentation checked on **2026-09-10**. The script has offline
mock coverage; it has not been deployed or live-tested against a customer environment.

This is a separate meeting walkthrough, not a replacement for the
[Terraform reference](../README.md). It uses existing resources rather than building
a new network. Running it changes the selected subscription's provider registration,
the named subnet's delegation and NSG association, and creates a NetworkSettings
resource. It does not create a resource group, VNet, subnet, NSG, private endpoint,
identity, or GitHub runner. It does not change NSG rules, DNS, routes, or role assignments.

## Before the session

- Install PowerShell 7 and a current Azure CLI. Sign in to the correct tenant with
  your own approved Azure identity before running the script.
- Have an existing resource group, VNet, dedicated empty runner subnet, and reviewed
  NSG in that resource group. The subnet must have no existing NICs, Private Endpoints,
  or conflicting service delegation. Use a **new** NetworkSettings resource name.
- Confirm the VNet is in a [supported APN region](https://docs.github.com/en/enterprise-cloud@latest/admin/configuring-settings/configuring-private-networking-for-hosted-compute-products/about-azure-private-networking-for-github-hosted-runners-in-your-enterprise#about-supported-regions).
  Size the subnet for maximum concurrency plus GitHub's 30 percent buffer and Azure's
  five reserved addresses. Private Endpoints belong in a different, nondelegated subnet.
- The existing NSG should explicitly deny inbound traffic. GitHub needs no inbound
  connections. Confirm working outbound connectivity, private DNS, and approved
  GitHub, Entra, ARM, and workload/package destinations before starting. This script
  neither provisions an outbound path nor checks the completeness of those controls.
- Confirm rights to register `GitHub.Network`, update the subnet/NSG association,
  and create NetworkSettings. Registration is subscription-wide; coordinate with its
  bootstrap owner. No Azure role is assigned by this script.
- Choose organization- or enterprise-level GitHub networking and obtain that scope's
  numeric `databaseId`. An enterprise can permit organization-owned configurations;
  otherwise use the enterprise configuration and enterprise ID. Do not use a display
  name, GraphQL node ID, or Azure subscription ID as `GitHubDatabaseId`.
- Confirm GitHub plan entitlement, larger-runner image/size availability, permissions,
  and billing budget. Larger-runner usage is billed separately from included minutes.
- Do not run this alongside Terraform against the same resources. Agree ownership
  and state reconciliation before using the walkthrough on an IaC-managed subnet.

## Run the Azure sequence

For an organization-owned configuration, its numeric ID can be read with an
already-authenticated GitHub CLI identity that has access to that organization:

```powershell
gh api graphql -f query='query($login: String!) { organization(login: $login) { databaseId } }' `
    -f login=YOUR-ORG --jq .data.organization.databaseId
```

For enterprise-owned networking, follow the
[enterprise setup guide](https://docs.github.com/en/enterprise-cloud@latest/admin/configuring-settings/configuring-private-networking-for-hosted-compute-products/configuring-private-networking-for-github-hosted-runners-in-your-enterprise)
to obtain the enterprise `databaseId` instead. No GitHub credential is passed to the
PowerShell setup script.

From this directory, replace every example value with the agreed existing resources:

```powershell
$setup = @{
    SubscriptionId = '11111111-1111-1111-1111-111111111111'
    ResourceGroupName = 'rg-example-eus'
    VirtualNetworkName = 'vnet-example-eus'
    SubnetName = 'snet-example-runners'
    NetworkSecurityGroupName = 'nsg-example-runners'
    NetworkSettingsName = 'github-example-eus'
    GitHubDatabaseId = '123456'
}

$result = ./github-preparation.ps1 @setup
$result | Format-List
```

The numbered sequence selects the subscription, resolves the existing resources,
registers `GitHub.Network` with `--wait`, delegates the subnet and attaches the NSG,
then creates NetworkSettings using the existing VNet's region. Every nonzero Azure
CLI exit stops the script. There is no automatic rollback of earlier successful
steps; inspect the reported step before retrying.

## Finish in GitHub

1. Open **Hosted compute networking** at the matching organization or enterprise.
   Create an Azure private network configuration and supply `$result.GitHubId` from
   the Azure resource's `tags.GitHubId`, **not** the subnet or NetworkSettings ARM ID.
2. Create a restricted runner group and select that network configuration. Allow
   only the repositories and trusted workflows intended for private access.
3. Create a GitHub-hosted **larger runner**, select an available image and size,
   leave static public IP disabled, and place it in that group, not the default group.
4. Set the workflow's `runs-on` to the new runner's name/label. Plain `ubuntu-latest`
   selects the standard hosted pool rather than this newly named APN runner.
5. Run an approved nonproduction smoke job: confirm private DNS and connectivity,
   then perform one intended OIDC-authorized operation without printing secret values.
   Validate the required denied paths before using it for privileged work.

## What changed from the older demo

| Item | Current treatment |
| --- | --- |
| Hardcoded account and resource values | Required input parameters; no customer identifiers or credentials |
| Region and subnet ARM ID | Read from the existing VNet/subnet instead of composed assumptions |
| Static GitHub IP Bicep template | Not copied. Current GitHub guidance recommends domain-based egress using `https://api.github.com/meta`; the old static lists are not maintained |
| Demo Internet-deny workaround | Not copied. Reuse the reviewed NSG and existing egress policy without changing rules |
| NetworkSettings API | `2024-04-02` remains the latest documented Azure version and the version in GitHub's current setup guide |
| PowerShell JSON escaping | Serialize once to a temporary UTF-8 file and use Azure CLI's documented `--properties @file --is-full-object` input |
| Provider registration | Wait for registration before subnet delegation |
| GitHub enterprise setup | Match the configuration scope and numeric ID; organizations can create configurations when enterprise policy allows |
| NIC visibility | Do not depend on seeing a NIC in the customer subscription; GitHub documents movement to service-subscription NICs using addresses from your subnet |
| Cleanup | No resource-group deletion command. Follow GitHub's documented detach/NetworkSettings removal order if teardown is separately approved |

## Offline validation

```powershell
./tests/github-preparation.tests.ps1
```

All Azure CLI commands are mocked. Tests check existing-resource inputs, delegation,
NSG reuse, current API and JSON shape, GitHub ID output, temporary-file cleanup, and
stopping after failed CLI operations. They do not prove live entitlement, permissions,
regional availability, network reachability, or successful APN provisioning.

## Current references

- [GitHub organization setup](https://docs.github.com/en/organizations/managing-organization-settings/configuring-private-networking-for-github-hosted-runners-in-your-organization)
- [GitHub architecture, supported regions, and enterprise policy](https://docs.github.com/en/enterprise-cloud@latest/admin/configuring-settings/configuring-private-networking-for-hosted-compute-products/about-azure-private-networking-for-github-hosted-runners-in-your-enterprise)
- [Azure NetworkSettings schema](https://learn.microsoft.com/en-us/azure/templates/github.network/networksettings)
- [Azure CLI resource creation](https://learn.microsoft.com/en-us/cli/azure/resource#az-resource-create)
- [Azure CLI quoting and JSON files](https://learn.microsoft.com/en-us/cli/azure/use-azure-cli-successfully-quoting)