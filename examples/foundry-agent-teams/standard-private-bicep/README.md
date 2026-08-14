# Standard private Foundry agent published to Teams with Bicep

This independent Bicep root is a generic client template for a Standard
Microsoft Foundry Agent Service with end-to-end private networking. It keeps
Azure resources in infrastructure as code and uses delegated PowerShell only
for the Foundry data-plane operations that ARM cannot represent.

Copy this directory by itself into the adopting repository. It has no runtime,
module, state, or deployment dependency on the sibling Terraform examples.

## Ownership boundary

| Surface | Owner |
|---|---|
| Foundry account, model deployment, project | `main.bicep` |
| Agent network injection | `main.bicep` |
| Storage, Cosmos DB, and AI Search project connections | `main.bicep` |
| Project and dependency RBAC | Bicep modules |
| Project capability host | `main.bicep` |
| Workload private endpoints and DNS zone groups | `modules/private-endpoints.bicep` |
| Azure Bot Service and Teams channel | `modules/bot-service.bicep` |
| Prompt Agent version and publication REST calls | `scripts/invoke-agent-publication.ps1` |

PowerShell does not create resource groups, subnets, private endpoints, Bot
Service, channels, role assignments, or any other ARM resource.

## What the main template creates

- one PNA-disabled `AIServices` Foundry account with local auth disabled;
- one model deployment;
- one system-assigned-identity Foundry project;
- `networkInjections.scenario = 'agent'` on the dedicated agent subnet;
- AAD project connections to client-owned Storage, Cosmos DB, and AI Search;
- Foundry User, Storage, Cosmos DB, and AI Search least-privilege assignments;
- one project capability host bound to those three connections;
- the Foundry private endpoint and, when selected, dependency private endpoints
  with client-owned private DNS zone groups;
- optionally, after agent configuration, one SingleTenant Azure Bot Service and
  `MsTeamsChannel`, both bound to `instance_identity.principal_id`.

The account-level capability host is created implicitly by the Cognitive
Services resource provider when it processes the `agent` network injection.
Only one account capability host is supported. Do not declare a second one.

## Required existing client resources

The client supplies full resource IDs for:

- a dedicated `/27` or larger RFC1918 subnet delegated exclusively to
  `Microsoft.App/environments` (`/24` is recommended);
- a separate private endpoint subnet;
- Storage, Cosmos DB, and Azure AI Search;
- private DNS zones for `services.ai`, `openai`, `cognitiveservices`, Storage
  blob, Cosmos DB, and Azure AI Search.

Set any `create*PrivateEndpoint` parameter to `false` when the platform already
owns a private endpoint for that dependency and the agent subnet can resolve and
reach it. The Foundry account private endpoint is always created because the
account itself belongs to this root.

The Foundry account and VNet must use the same supported Azure region. Check
every address prefix on the VNet and every peered VNet against Microsoft's
reserved ranges, including `100.64.0.0/11`.

Pass platform-owned subnet IDs directly to `main.bicep`. This root does not
modify the client VNet, route tables, NSGs, or shared DNS zones.

Register `Microsoft.CognitiveServices`, `Microsoft.App`,
`Microsoft.ContainerService`, `Microsoft.Network`, `Microsoft.BotService`,
`Microsoft.Storage`, `Microsoft.DocumentDB`, and `Microsoft.Search` before the
first deployment.

## Staged deployment

Run deployments from the client's protected infrastructure pipeline. The Azure
CLI commands below show the contract; they are not a substitute for required
approvals, what-if review, policy checks, or separation of deployment identities.

### Stage 1 - Standard Agent Service foundation

Keep `agentPrincipalId = ''` in `main.bicepparam`. Review a what-if, then deploy
the Foundry foundation:

```powershell
az deployment group what-if `
  --resource-group <foundry-resource-group> `
  --template-file main.bicep `
  --parameters main.bicepparam

az deployment group create `
  --resource-group <foundry-resource-group> `
  --template-file main.bicep `
  --parameters main.bicepparam
```

Network-injected capability-host provisioning can take 30-35 minutes. A long
deployment is not by itself evidence of a hang.

### Stage 2 - delegated Prompt Agent configuration

From a machine that resolves the Foundry private endpoint, sign in as the human
publisher with `az login`. Preview first:

```powershell
./scripts/invoke-agent-publication.ps1 `
  -Operation Configure `
  -ProjectEndpoint <main-output-projectEndpoint> `
  -AgentName <agent-name> `
  -ModelDeploymentName <model-deployment-name> `
  -BotName <bot-name> `
  -AgentDisplayName '<display-name>'
```

Add `-Execute` only after reviewing the identity, subscription, endpoint, and
payload. Execute creates a Prompt Agent version, enables `activity`, `responses`,
and `BotServiceRbac`, then writes `agent-handoff.parameters.json`. The handoff
contains no credential or token.

### Stage 3 - Bot Service through Bicep

Pass the handoff after the base parameter file so its four values override the
empty Stage 1 values:

```powershell
az deployment group what-if `
  --resource-group <foundry-resource-group> `
  --template-file main.bicep `
  --parameters main.bicepparam '@agent-handoff.parameters.json'

az deployment group create `
  --resource-group <foundry-resource-group> `
  --template-file main.bicep `
  --parameters main.bicepparam '@agent-handoff.parameters.json'
```

The second deployment adds Bot Service and the Teams channel. It does not
recreate the Foundry account or project.

### Stage 4 - delegated Microsoft 365 publication

Preview the exact metadata first, then repeat with `-Execute`:

```powershell
./scripts/invoke-agent-publication.ps1 `
  -Operation Publish `
  -ProjectEndpoint <main-output-projectEndpoint> `
  -AgentName <agent-name> `
  -ModelDeploymentName <model-deployment-name> `
  -BotName <bot-name> `
  -AgentDisplayName '<display-name>' `
  -BotServiceArmId <main-output-botServiceResourceId> `
  -DeveloperName '<organization>' `
  -DeveloperWebsiteUrl 'https://example.com' `
  -PrivacyUrl 'https://example.com/privacy' `
  -TermsOfUseUrl 'https://example.com/terms'
```

The script refuses service-principal and managed-identity Azure CLI sessions.
Every REST call has a caller-controlled timeout. A successful response must
contain `titleId`.

### Stage 5 - private channel ingress

Step 4 publishes the app package, but a PNA-disabled agent cannot answer Teams
messages until the Microsoft Bot Channel Adapter can reach its private activity
endpoint through an approved public TLS entry point and reverse proxy. Reuse the
client's Application Gateway, compatible APIM deployment, firewall plus proxy,
or equivalent architecture. This example does not create a gateway product.

Keep the Bot Service `endpoint` set to the Foundry activity-protocol URL from
Step 2. Step 5 publishes DNS and routes that hostname through the client's entry
point; it does not substitute a different proxy URL in Bot Service.

Restrict ingress to the documented Microsoft channel-adapter ranges and validate
Bot Framework JWTs before crossing a required security boundary. Validate a real
Teams reply; `titleId` alone is not end-to-end completion.

## Validation

```powershell
az bicep build --file main.bicep --stdout > $null
az bicep build-params --file main.bicepparam --stdout > $null
python ../../../.github/scripts/test_foundry_agent_teams_bicep.py
```

## Rollback

Stop before deployment when what-if proposes changes outside the adopting
workload boundary. To remove an already deployed network-injected account, first
remove the project capability host, then purge the Foundry account and wait for
the account capability host to release the delegated subnet. Do not delete or
recreate a client-owned VNet, DNS zone, Storage account, Cosmos DB account, or
AI Search service as a rollback shortcut.

## Sources

- https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks
- https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot-virtual-network
- https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep/15-private-network-standard-agent-setup

See `THIRD-PARTY-NOTICES.md` for the upstream sample license notice.
