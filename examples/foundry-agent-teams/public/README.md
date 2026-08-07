# Public Microsoft Foundry Prompt Agent published to Teams

This standalone Terraform root creates the Azure control-plane foundation for a
public Microsoft Foundry Prompt Agent and its native Microsoft Teams / Microsoft
365 publication path. It is a generic reference template, not deployed customer
infrastructure.

## What this root manages

- one resource group through Resource Group AVM `0.4.0`;
- one public Microsoft Foundry account, project, and model deployment through
  Foundry pattern AVM `0.11.2`;
- zero or more SingleTenant Azure Bot Service resources through Bot Service AVM
  `0.4.0` after Prompt Agent identities exist;
- one `MsTeamsChannel` child for each Bot Service;
- deterministic Foundry project and activity protocol endpoints;
- static ownership tags. AVM resources carry `LastAppliedStamp=Disabled` because
  module blocks cannot ignore a CI-managed tag.

Terraform does **not** create the Prompt Agent, toolbox, project connection, or
Microsoft 365 catalog publication. Those are Foundry data-plane operations and
belong in the staged GitHub Actions workflow. Do not add `local-exec` or a
Terraform provisioner to perform them.

## Required inputs

Copy `terraform.tfvars.example` and set the subscription, tenant, region,
resource names, and a model/version that has quota in that region. The first
apply keeps `agent_publications = {}`. After the data-plane stage creates the
Prompt Agent, add the returned `instance_identity.principal_id`, reviewed bot
name, and display name under the Prompt Agent's name.

## Deployment sequence

1. Run source validation and a reviewed plan with `agent_publications = {}`.
2. Apply the Foundry foundation through the protected GitHub Environment.
3. Apply the repository-owned MCP connection, toolbox, and Prompt Agent
   definitions. Verify the tool allowlist and capture the agent principal ID.
4. Run a second Terraform plan with `agent_publications` populated. Review the
   new Bot Service and Teams channel, then apply that exact plan.
5. Call `POST /agents/{name}/microsoft365/publish?api-version=v1` with the Bot
   Service ARM ID. Start with `publishScope=Shared`.
6. Confirm the app appears under **Your agents**, then send a real Teams message
   and verify the expected MCP-backed reply. A publish `titleId` alone is not an
   end-to-end test.

## Source validation

```bash
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate -no-color
terraform test -no-color
```

The template intentionally ships no backend and no dependency lockfile. The
adopting repository generates and reviews its own lockfile, adds its same-
subscription backend, and uses the starter's OIDC plan/apply workflow.

## Rollback

Before publication, remove the new Prompt Agent version and revert the source
commit. After publication, return traffic to the prior stable agent version or
remove the new catalog version before considering infrastructure deletion. Do
not delete and recreate the Teams channel as routine rollback; re-enabling it can
invalidate stored channel identifiers.

## References

- https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot-virtual-network
- https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol
- https://registry.terraform.io/modules/Azure/avm-ptn-aiml-ai-foundry/azurerm/0.11.2
- https://registry.terraform.io/modules/Azure/avm-res-botservice-botservice/azurerm/0.4.0