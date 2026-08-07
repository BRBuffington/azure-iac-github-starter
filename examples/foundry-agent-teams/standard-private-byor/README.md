# Standard/BYO private Foundry Prompt Agent published to Teams

This standalone Terraform root composes a Standard Microsoft Foundry Agent Setup
against an existing virtual network and customer-owned Storage, Cosmos DB,
Azure AI Search, Key Vault, and Private DNS zones. It is a generic reference
template, not deployed customer infrastructure.

## What this root manages

- one resource group through Resource Group AVM `0.4.0`;
- one PNA-disabled Microsoft Foundry account, project, model deployment,
  capability hosts, project connections, RBAC, and private endpoints through
  Foundry pattern AVM `0.11.2`;
- a dedicated Foundry `agent` network injection;
- private endpoints and zone groups for the existing BYOR dependencies;
- zero or more SingleTenant Azure Bot Service resources and `MsTeamsChannel`
  children through Bot Service AVM `0.4.0` after agent identities exist;
- repository-owned toolbox, Prompt Agent, and publication payloads applied by
  the shared `foundry-agent-data-plane.yml` workflow from an in-VNet runner.

The separate MCP subnet hosts the internal Container Apps environment or other
approved private MCP runtime. It is delegated to `Microsoft.App/environments`,
but it is not a second Foundry network injection. The agent subnet, private
endpoint subnet, and MCP subnet must be distinct.

## Required existing resources

Provide full resource IDs for the three subnets, Storage, Cosmos DB, Azure AI
Search, Key Vault, and the seven required Private DNS zones. The Foundry account
and virtual network must be in the same Azure region. The agent subnet must be
dedicated to one Foundry account, use a supported RFC1918 range, and be `/27` or
larger (`/24` is the Microsoft recommendation). Do not use CGNAT address space.

The root creates private endpoints for the Foundry account and each BYOR
dependency. If a platform team already owns those endpoints, adapt the root under
review rather than creating duplicates.

## Channel ingress boundary

Private Link is not supported for Teams or Azure Bot Service channel delivery.
Keep Foundry and its dependencies private, but provide one approved public TLS
ingress that can route to the Foundry activity endpoint. Reuse an existing
Application Gateway, compatible API Management deployment, firewall plus proxy,
or equivalent capability. This generic root does not create a new gateway
product by default.

Restrict inbound traffic to Microsoft channel-adapter ranges, prefer full Bot
Framework JWT validation before traffic crosses the private boundary, validate
the tenant, and allow the documented outbound identity and Bot Framework FQDNs.
Run the data-plane workflow on a self-hosted runner that resolves every private
endpoint correctly.

## Deployment sequence

1. Validate and apply the private Foundry foundation with
   `agent_publications = {}` through the protected environment.
2. From the in-VNet runner, apply the OAuth connection, toolbox, and Prompt Agent
   definitions. Validate `tools/list`, the allowlist, OAuth consent, and a real
   tool call; retain the generated principal-ID handoff artifact.
3. Run and review the second Terraform plan with the handoff file. Apply the Bot
   Service and Teams channel only after that plan is approved.
4. Configure and validate the customer-owned public ingress.
5. Dispatch the `publish` operation, which calls
   `POST /agents/{name}/microsoft365/publish?api-version=v1`, with
   `publishScope=Shared` and the Bot Service ARM ID.
6. Send a real Teams message and verify inbound delivery, approved MCP execution,
   and the outbound reply. A green apply or publication `titleId` is incomplete.

## Source validation

```bash
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate -no-color
terraform test -no-color
```

## Hold and rollback

Hold if the organization rejects the required public channel ingress, any name
resolves publicly from the in-VNet runner, OAuth consent or Conditional Access
cannot complete in Teams, or the MCP server exposes tools outside the allowlist.
Rollback the ingress route and return to Foundry-only testing first. Do not enable
public access on Foundry, Storage, Search, Cosmos DB, Key Vault, or the MCP service
as a recovery shortcut.

## References

- https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks
- https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot-virtual-network
- https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol
- https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-terraform/19-private-network-agent-setup-with-tools
- https://registry.terraform.io/modules/Azure/avm-ptn-aiml-ai-foundry/azurerm/0.11.2