# Foundry agent-to-Teams Bicep implementation notes

Continuous decision log. Newest entries appear first.

## 2026-08-14 - Preserve the Foundry activity endpoint through Step 5

Microsoft's publication guide requires Bot Service to retain the Foundry
activity-protocol URL. Public ingress makes that hostname reachable through DNS,
DNAT, TLS, and reverse proxy; it is not a replacement Bot Service endpoint.

## 2026-08-14 - Keep the customer template narrow

Removed the diagnostics collector, CIDR engine, subnet attachment, and shared
Checkov-wrapper expansion after they exceeded the requested template boundary.
The shipped surface is the parameterized Bicep deployment, delegated REST-only
publication script, example inputs, documentation, and focused validation.

## 2026-08-14 - Keep shared platform resources as client inputs

The root creates workload private endpoints and DNS zone groups but accepts the
VNet, dedicated subnets, BYOR services, and private DNS zones by resource ID.
It does not modify platform-managed VNets, subnets, route tables, NSGs, or DNS
zones.

## 2026-08-14 - Scope cross-subscription RBAC through modules

Bicep rejects deployable resources whose scope differs from the root file. Each
Storage, Cosmos DB, and AI Search assignment therefore runs in a module scoped
to the owning resource group, supporting same-tenant resources in separate
subscriptions without imperative role-assignment commands.

## 2026-08-14 - Keep optional infrastructure off the Step 4 proof path

The client root implements the Standard Agent Service resources required for a
private publication proof. ACR and Azure Monitor Private Link Scope remain
optional follow-ons because neither participates in Steps 1-4 and copying them
would make the client template larger without improving the publication test.

## 2026-08-14 - Keep the proven topology in Bicep

The third example remains Bicep rather than translating the architecture to
Terraform. Bicep owns all ARM-supported resources; delegated PowerShell is
limited to the Foundry data-plane operations that ARM cannot represent.

## 2026-08-14 - Use an independent client root

The Bicep option is a third copyable root, not a mode or module dependency of
the two Terraform examples. This preserves the starter repository's established
separate-root contract and lets a client adopt the Bicep proof independently.
