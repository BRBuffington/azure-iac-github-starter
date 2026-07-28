# Cross-tenant Private Link DNS implementation notes

## 2026-07-28 - Terraform MCP changed the implementation boundary

Terraform MCP returned current AVM versions and provider schemas before any
Terraform was authored. Its module source confirmed that Private Endpoint AVM
`0.2.0` fixes `is_manual_connection=false`; AzureRM exposes the required manual
flag and request message. The example therefore composes AVM for DNS and uses a
single raw-resource exception for the cross-tenant approval request.

## 2026-07-28 - Preserve central governance without merging DNS authority

The Azure template owns consumer-local zones, links, endpoints, and optional
resolver endpoints. It does not configure an enterprise DNS vendor. Outbound
resolver rules reject Azure service and `privatelink.*` namespaces so a copied
template cannot recreate whole-zone cross-context forwarding by accident.

## 2026-07-28 - Make invalid composition fail before provider calls

Cross-variable validations now bind each subresource to the correct zone,
require the ADLS Gen2 Blob companion for every DFS target, validate full provider
resource IDs, and reject forwarding rules without a resolver outbound subnet.
Only requested zones are created. The PR workflow validates this example and
honors an AVM-specific opt-out from the external `LastApplied` tag stamp.

Checkov `CKV_TF_1` requires Git module sources pinned by commit, which conflicts
with the repository decision to consume official AVMs from Terraform Registry
at exact MCP-verified versions. Each AVM block carries a local, explained
exception; no repository-wide policy is disabled.

## 2026-07-28 - Validate the CD config selector before reuse

The existing workflow reused the dispatch config in paths and artifact names;
the AVM stamp filter added another JMESPath use. Plan and apply now reject
non-basename selectors and missing config files before any of those consumers,
closing both path traversal and query-literal injection.