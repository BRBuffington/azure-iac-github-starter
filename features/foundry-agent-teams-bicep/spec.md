# Parameterized Bicep Foundry agent-to-Teams reference

**Status:** IMPLEMENTED

## Goal

Add a third, independent example under `examples/foundry-agent-teams/` that
preserves the proven Standard network-secured Microsoft Foundry architecture in
Bicep and removes every customer-specific value. The adopting client supplies
names, resource IDs, metadata, and topology through parameters.

## Ownership boundary

- Bicep owns every supported Azure control-plane resource: Foundry account,
  model deployment, project, Standard Agent Service network injection,
  customer-owned dependency connections and RBAC, capability host, private
  endpoints and DNS zone groups, Bot Service, and Teams channel.
- PowerShell owns only Foundry data-plane operations without an ARM resource:
  create or read the Prompt Agent, enable the activity protocol and
  authorization scheme, and call the Microsoft 365 publish API.
- The script is preview-only unless the operator supplies `-Execute`; it never
  creates or mutates Azure control-plane resources.

## Deployment contract

1. Deploy the Standard network-secured foundation with an empty
   `agentPrincipalId`.
2. Run the delegated PowerShell configure operation to create/read the Prompt
   Agent and capture `instance_identity.principal_id`.
3. Re-run the Bicep deployment with that principal ID so Bicep creates Bot
   Service and `MsTeamsChannel`.
4. Run the delegated PowerShell publish operation with `publishScope=Shared`.
5. Treat a returned `titleId` as publication evidence only; a real Teams reply
   is the acceptance test.

## Constraints

- The Foundry account remains `publicNetworkAccess=Disabled`.
- Agent compute uses a dedicated RFC1918 subnet delegated to
  `Microsoft.App/environments` through `networkInjections.scenario='agent'`.
- The client supplies existing VNet, BYOR dependency, and private DNS zone
  resource IDs; this example does not create or own shared platform resources.
- No Terraform, `local-exec`, deployment script resource, client secret, key,
  imperative ARM write, or embedded customer identifier is allowed.
- The root is copyable without a dependency on either sibling example.

## Success criteria

- `az bicep build` compiles `main.bicep` and the example parameter file.
- Deterministic tests prove the network injection, capability host, connection,
  RBAC, private endpoint, Bot Service, Teams channel, delegated-token, and
  preview/execute contracts.
- The catalog and root README explain the staged deployment and rollback.
- No existing example, state, or live Azure resource is changed.
