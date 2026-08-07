# Microsoft Foundry agent to Teams starter

This directory is a catalog of two independent Terraform roots for publishing a
Microsoft Foundry Prompt Agent to Microsoft Teams and Microsoft 365 Copilot.
Choose one child root and copy only that root into the adopting repository.

- [`public/`](public/) is the lowest-complexity functional pilot. The Foundry
  project and remote MCP endpoint remain publicly reachable and are protected by
  Microsoft Entra authentication and an explicit tool allowlist.
- `standard-private-byor/` is the Standard Agent Setup for an existing virtual
  network, customer-owned Storage, Cosmos DB, and Azure AI Search, private
  endpoints, and a private MCP endpoint. It is added and validated independently
  from the public root.

The roots do not share modules, variables, or state. They demonstrate the same
staged publication contract:

1. Terraform provisions the Foundry control-plane resources.
2. A reviewed GitHub Actions stage applies the repository-owned connection,
   toolbox, and Prompt Agent definitions through current first-party data-plane
   commands or REST APIs.
3. The workflow reads `instance_identity.principal_id` from the created agent.
4. Terraform creates Azure Bot Service and its Microsoft Teams channel with that
   principal ID and the agent activity endpoint.
5. The workflow calls the current Microsoft 365 publish API and verifies a real
   Teams conversation.

Terraform does not use `local-exec` or provisioners for data-plane operations.
The repository definitions are authoritative, but Foundry does not watch Git;
the workflow must reapply changed definitions.

## References

- https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot-virtual-network
- https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol
- https://learn.microsoft.com/azure/foundry/agents/how-to/use-cli-with-coding-agents
- https://aka.ms/avm