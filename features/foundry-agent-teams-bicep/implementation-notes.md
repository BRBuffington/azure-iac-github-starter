# Foundry agent-to-Teams Bicep implementation notes

Continuous decision log. Newest entries appear first.

## 2026-08-14 - Restore the promised network evidence collector

The initial recommendation included a read-only collector for PNA, network
injection, local and peered VNet CIDRs, roles, and flow-log configuration. It
was incorrectly removed while narrowing the overbuilt first implementation.
The collector is restored without changing Jonathan's deployment graph. It
lists Azure Network Watcher VNet flow logs; new NSG flow logs are retired, and
logs cannot recover traffic from before enablement.

An August 14 customer troubleshooting meeting moved the observed Step 4 response
from an earlier 502 to `dependency_error` / 403 with `Copilot extensibility is
not enabled for this user`, but it did not prove whether those responses share a
cause or which Microsoft 365 control produced the 403. Prechecks now preserve
the status, service code, and request ID while explicitly refusing to classify
the cause. The meeting also confirmed that recreating Step 2 produced the
expected MSA app ID, tenant, and activity endpoint, so the Bicep resource shape
did not change.

Five troubleshooting attachments were recovered from the July 23 and July 30
email thread: three architecture PDFs, `create_toolbox.py`, and a screenshot of
that same source. The PDFs confirm that network injection must be present when
the hosted-agent account is created and that MCP OAuth state is a separate
credential layer; neither establishes the Step 4 403 cause.

## 2026-08-14 - Use the proven baseline with ergonomic IaC defaults

Fidelity is not the end goal. Jonathan's working package remains the MVP and
troubleshooting baseline, while targeted improvements are encouraged when they
reduce client work without hiding the proven flow. Step 2 stays in Bicep;
standard names, metadata, model settings, SKUs, and DNS resource-group reuse now
have clean defaults or shorthands. Resource IDs, CIDRs, and runtime identity
values remain explicit because guessing them would be unsafe.

Resource names follow the same composition pattern as Terraform locals:
workload, organization-defined region, and environment inputs feed
resource-specific name variables, with full-name parameters retained only as
escape hatches. Resource-type prefixes are grounded in the current Microsoft
CAF abbreviation table; definite upstream mismatches (`acr`, `law`, and
suffix-style private endpoint names) were corrected to `cr`, `log`, and `pep`.

## 2026-08-14 - Replace the rewrite with the working package

The first implementation re-created Jonathan's architecture and over-expanded
the original task. It is replaced by his exact foundation, network attachment,
and Step 1-4 script; only client parameters and Bicep-owned Step 2 are adapted.

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
