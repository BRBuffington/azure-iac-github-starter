# Private Foundry agent to Teams - Bicep template

This is a client-neutral version of the Bicep and PowerShell package that has
successfully published a network-isolated Microsoft Foundry agent through Step 4.

The package keeps Azure resources in Bicep:

- `foundation/` deploys the Standard network-secured Foundry account, project,
  dependencies, private endpoints, capability hosts, and RBAC.
- `network/` optionally adds the dedicated
  `Microsoft.App/environments` agent subnet to an existing VNet.
- `bot-service.bicep` deploys Azure Bot Service and `MsTeamsChannel`.
- `scripts/oneThroughFour.ps1` reads the existing agent identity, verifies the
  Bicep-owned Bot Service, patches the activity protocol, and calls the
  Microsoft 365 publish API.

The Bicep files provide client-neutral defaults for resource names, project
metadata, model settings, SKUs, and feature switches. The `.bicepparam` files
contain only environment facts that cannot be defaulted safely, such as an
existing resource ID, a subnet CIDR, or the identity returned by Step 1. Add an
override to a parameter file only when the client needs to differ from the
default.

Default resource names are composed from `workloadName`, `locationShortName`,
and `environmentName`, then receive a resource-type prefix and deterministic
resource-group suffix. Set those three values once to rename the deployment
consistently. `resourceNamePrefix`, `aiServices`, and `firstProjectName` remain
available as clean overrides for an established client convention or an
existing resource. When changing `location`, also set the organization's
corresponding `locationShortName` token.

Resource-type prefixes follow Microsoft Cloud Adoption Framework guidance:
`aif`, `proj`, `srch`, `cosno`, `st`, `cr`, `appi`, `log`, `pep`, `vnet`,
`snet`, and `bot`. This starter consistently orders the remaining components as
workload, region, environment, then an instance or deterministic uniqueness
token.

For centralized private DNS, set one resource group with
`existingDnsZonesResourceGroup` and `existingMonitorDnsZonesResourceGroup`.
Use the `existingDnsZones` maps only for per-zone exceptions. Omit all four
inputs when the deployment should create its own zones.

## Sequence

### 1. Deploy the private Foundry foundation

Edit `foundation/main.bicepparam`, then run a what-if and deployment through the
client's normal Bicep pipeline:

```powershell
az deployment group what-if `
  --resource-group <foundry-resource-group> `
  --template-file foundation/main.bicep `
  --parameters foundation/main.bicepparam

az deployment group create `
  --resource-group <foundry-resource-group> `
  --template-file foundation/main.bicep `
  --parameters foundation/main.bicepparam
```

If the platform team has already created the VNet and both default-named
subnets, only its resource ID is required. Override `agentSubnetName` or
`peSubnetName` when the client uses different names. Otherwise, set the VNet
name and an explicitly approved, non-overlapping CIDR in
`network/foundry-private-agent.bicepparam`, then deploy that template first.

### 2. Read the agent identity

Create and test the Prompt Agent in the deployed project. Run the script without
`-Execute` from a machine that resolves the private project endpoint:

```powershell
./scripts/oneThroughFour.ps1 `
  -ProjectEndpoint 'https://<account>.services.ai.azure.com/api/projects/<project>' `
  -AgentName '<agent-name>' `
  -BotName '<bot-name>' `
  -BotResourceGroup '<bot-resource-group>' `
  -DeveloperName '<organization>' `
  -DeveloperWebsiteUrl 'https://example.com' `
  -PrivacyUrl 'https://example.com/privacy' `
  -TermsOfUseUrl 'https://example.com/terms'
```

Preview prints `Principal ID`, `Tenant ID`, and the activity endpoint. Copy those
values into `bot-service.bicepparam`.

### 3. Deploy Bot Service with Bicep

```powershell
az deployment group what-if `
  --resource-group <bot-resource-group> `
  --template-file bot-service.bicep `
  --parameters bot-service.bicepparam

az deployment group create `
  --resource-group <bot-resource-group> `
  --template-file bot-service.bicep `
  --parameters bot-service.bicepparam
```

### 4. Publish

Repeat the Step 2 command with `-Execute`. The script verifies the Bicep-owned
bot and Teams channel, enables `activity` plus `BotServiceRbac`, and publishes
with `publishScope=Shared`. Success returns a `titleId` and `teamsAppId`.

Step 5 public ingress is a separate client architecture decision and is not
included in this Step 4 template.

## Validation

```powershell
az bicep build --file foundation/main.bicep --stdout > $null
az bicep build-params --file foundation/main.bicepparam --stdout > $null
az bicep build --file network/foundry-private-agent.bicep --stdout > $null
az bicep build-params --file network/foundry-private-agent.bicepparam --stdout > $null
az bicep build --file bot-service.bicep --stdout > $null
az bicep build-params --file bot-service.bicepparam --stdout > $null
```

## Sources

- https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep/15-private-network-standard-agent-setup
- https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot-virtual-network
- https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming
- https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations

See `THIRD-PARTY-NOTICES.md` for the upstream license.