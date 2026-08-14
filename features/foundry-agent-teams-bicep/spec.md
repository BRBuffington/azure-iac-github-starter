# Parameterized Bicep Foundry agent-to-Teams reference

**Status:** IMPLEMENTED

## Goal

Add a smooth, client-agnostic Step 4 example under
`examples/foundry-agent-teams/` using the already-working private Foundry Bicep
package and `oneThroughFour.ps1` as the baseline. Preserve that proven
troubleshooting path while improving individual steps where IaC is simpler and
clearer.

## Ownership boundary

- Jonathan's foundation, optional modules, and troubleshooting flow remain the
  baseline; parameter UX may improve without redesigning the resource graph.
- A small Bicep template owns Bot Service and the Teams channel for Step 2.
- Jonathan's script reads the agent identity, verifies Step 2, patches the
  activity protocol, and calls the Step 4 publish API.
- A separate read-only collector reports PNA, network injection, private
  endpoints, subnet delegation, VNet and peered-VNet CIDRs, visible roles, and
  Network Watcher VNet flow-log configuration without mutating Azure.
- Basic names, metadata, model choices, SKUs, and feature switches have
  overridable client-neutral defaults. Resource IDs, CIDRs, and runtime identity
  values remain explicit.
- Default names compose a resource-type prefix with workload, CAF-style region,
  environment, and deterministic uniqueness tokens; full-name overrides remain
  available for client exceptions.

## Deployment contract

1. Deploy the Standard network-secured foundation.
2. Run `oneThroughFour.ps1` in preview to read the existing agent identity.
3. Deploy Bot Service and `MsTeamsChannel` with Bicep using the Step 1 values.
4. Repeat the script with `-Execute` to perform Steps 3 and 4.

## Constraints

- The Foundry account remains `publicNetworkAccess=Disabled`.
- Agent compute uses a dedicated RFC1918 subnet delegated to
  `Microsoft.App/environments` through `networkInjections.scenario='agent'`.
- The client supplies existing VNet, BYOR dependency, and private DNS zone
  resource IDs; this example does not create or own shared platform resources.
- No Terraform translation, client secret, key, imperative ARM write, or
  embedded customer identifier is allowed.
- The root is copyable without a dependency on either sibling example.
- The example parameter files specify only client facts that cannot be safely
  inferred or defaulted.
- Publication errors remain observed evidence. The template does not infer that
  sequential 502 and 403 responses share or do not share a root cause.

## Success criteria

- `az bicep build` compiles `main.bicep` and the example parameter file.
- CI compiles the foundation, network attachment, and Bot Service templates and
  parses the PowerShell script.
- Deterministic contracts keep the collector read-only, require VNet rather
  than retired NSG flow-log discovery, and preserve the non-diagnostic error
  boundary.
- A client can start from the example parameter files without restating basic
  template defaults, while retaining clean overrides for every exposed option.
- The catalog and root README explain the staged deployment and rollback.
- No existing example, state, or live Azure resource is changed.
