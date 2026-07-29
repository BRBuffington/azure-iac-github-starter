# Cross-tenant Private Link DNS starter

This directory is a catalog of two independent Terraform roots for
cross-tenant Azure Private Link DNS. Choose one option and copy only that child
directory into the client repository. The parent directory contains no
deployable Terraform and no architecture selector.

## Design contract

- Keep one enterprise DNS control plane if required, but preserve separate
  resolution contexts for each consumer network.
- Forward the public service zones (`dfs.core.windows.net`,
  `blob.core.windows.net`, and `database.windows.net`) from enterprise DNS to
  the appropriate consumer resolver. Do not forward one tenant's complete
  `privatelink.*` zones to every client.
- Create consumer-local Private Endpoints by full provider resource ID. The
  provider independently approves each pending connection.
- Choose exactly one child implementation and one DNS record owner per
  deployment. Do not compose the two roots together.
- ADLS Gen2 requires both `dfs` and `blob` endpoints and zones.
- Applications keep using normal service FQDNs. Azure SQL clients use
  `<server>.database.windows.net`, never a raw private IP or the
  `privatelink` FQDN.
- Resolver outbound rules are only for enterprise-owned namespaces that Azure
  must resolve through central DNS.

## Choose the DNS architecture

### Option A: [`standard-contexts/`](standard-contexts/)

Use this standalone root when enterprise DNS can classify clients into stable
consumer contexts or send them to distinct service listeners. Enterprise DNS
forwards the public service zones to same-authority consumer resolver
endpoints. Standard `privatelink.*` zones stay linked to the consumer VNet, and
each Private Endpoint zone group owns its records.

Query flow:

```text
client -> enterprise DNS context -> public service-zone forward
     -> consumer Resolver -> standard privatelink zone -> local PE IP
```

This is the baseline architecture because it keeps Microsoft's normal service
FQDNs and Azure-managed record lifecycle.

### Option B: [`prefixed-backing/`](prefixed-backing/)

Use this standalone root only for an explicit resource allowlist when one
context must represent multiple same-named authorities or a measured
requirement needs health- or topology-aware endpoint selection. Terraform
creates tenant- or region-prefixed backing zones and explicit A records.
Enterprise DNS separately owns the exact bridge from the standard
`privatelink` target to the prefixed name or selected endpoint.

Query flow:

```text
client -> normal Azure service FQDN -> public CNAME -> standard privatelink target
     -> exact enterprise DNS bridge -> prefixed backing record or selected PE IP
```

A prefixed zone alone is incomplete because Azure public DNS continues to
target the standard `privatelink` name. Do not use wildcard capture of
`*.privatelink.*`, and do not attach a standard zone group in this mode.

Option B is deliberately two phase:

1. Keep `approved_private_endpoint_target_keys` empty and apply the
  consumer-local Private Endpoint requests without DNS records.
2. The provider validates and approves each request.
3. Verify `Approved` through Azure, add the approved target keys to
  `approved_private_endpoint_target_keys`.
4. Apply the prefixed zones and records for those approved targets, then
  configure and validate the exact enterprise DNS bridge. Previously published
  targets remain in place while newly added targets wait for approval.

The approval-key input is a pipeline gate, not independent proof. The delivery
workflow must capture the live Azure connection state before the publication
phase.

## Terraform MCP and AVM sources

The template uses current Terraform MCP catalog examples and pins:

- [Private DNS Zone AVM 0.5.0](https://github.com/Azure/terraform-azurerm-avm-res-network-privatednszone)
- [DNS Resolver AVM 0.8.0](https://github.com/Azure/terraform-azurerm-avm-res-network-dnsresolver)
- [Private Endpoint AVM 0.2.0](https://github.com/Azure/terraform-azurerm-avm-res-network-privateendpoint)

The Private Endpoint AVM currently hardcodes automatic approval. Cross-tenant
consumers normally require `is_manual_connection = true`, so
each child root contains its own `cross_tenant_private_endpoints.tf` direct
AzureRM exception based on the provider schema returned by Terraform MCP.

## Use

Run from the selected child directory only:

```bash
cd standard-contexts  # or: cd prefixed-backing
cp terraform.tfvars.example terraform.tfvars
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate -no-color
terraform test -no-color
terraform plan -input=false -out=tfplan
terraform show -json tfplan > tfplan.json
```

The starter does not ship `.terraform.lock.hcl`. `terraform init` generates the
consumer repository's dependency lockfile from the constraints in
`z_versions.tf`; review that generated file under the consumer repository's
normal dependency policy.

Each child `terraform.tfvars.example` contains only deployment facts: Azure
resource IDs, names, flags, a DNS label/TTL where applicable, and optional DNS
server addresses. The fixed DFS, Blob, SQL, zone, record, and forwarding-rule
maps live in `z_locals.tf`; root resources consume those named locals. Extend
the locals when adapting the starter instead of adding nested object-map inputs.

Do not apply this example locally. Integrate it into the governed pipeline in
the repository root, using the backend and caller templates from
[terraform-pipelines-github](https://github.com/BRBuffington/terraform-pipelines-github/tree/main/templates).

When integrating, pass the pipeline's static `DeployedByRepo` and
`DeployedConfig` ownership tags through `var.tags`. The raw Private Endpoint
ignores the CI-managed `LastApplied` tag. The pinned AVMs do not expose
resource-level lifecycle metadata, so their resources carry
`LastAppliedStamp=Disabled`; the starter pipeline honors that marker and leaves
their static ownership tags intact without creating perpetual plan drift.

## Provider and consumer sequence

1. The provider supplies verified Storage account and SQL logical-server
   resource IDs and the required subresources.
2. The consumer runs a reviewed plan, then creates pending `dfs`, `blob`, and
   `sqlServer` Private Endpoint requests.
3. The provider validates the requesting tenant/subscription and approves the
   pending connections.
4. For Option A, the consumer verifies Azure-managed standard zone records and
  enterprise DNS forwards each public service zone to the correct consumer
  resolver context.
5. For Option B, the consumer verifies `Approved`, enables the record
  publication gate, applies prefixed zones and records, and configures the
  exact standard-name bridge in enterprise DNS.
6. The consumer validates routes, NSGs, firewalls, identity, service
  authorization, cache behavior, and application transactions independently
  of DNS success.

## Validation matrix

From every representative client population:

```text
nslookup <storage>.dfs.core.windows.net
nslookup <storage>.blob.core.windows.net
nslookup <server>.database.windows.net
```

Required evidence:

- the expected consumer-local private IP for each FQDN;
- no NXDOMAIN or unintended public fallback for private-only resources;
- TCP 443 to both Storage endpoints;
- TCP 1433 for Azure SQL Proxy, or the approved Redirect port range;
- successful DFS and Blob operations and an authorized SQL login;
- no regression to unrelated names in either DNS context.

Option B also requires:

- the normal service-name chain reaches the exact standard-name bridge and the
  intended prefixed record;
- endpoint replacement produces a reviewed Terraform record change;
- no unknown or unrelated `privatelink` name is intercepted;
- monitor-path-only failure, client-path-only failure, all-targets-down,
  positive and negative cache expiry, failover, and failback are observed;
- every endpoint that DNS can select passes an authenticated service
  transaction and satisfies the documented data-currency and read/write role.

Hold if the provider resource IDs, DNS context, source ranges, route, firewall,
approval owner, service-native failover behavior, or record owner are unknown.
For Option A, roll back the new enterprise forwarding context first. For Option
B, disable the exact bridge or health policy first and restore the prior record
export. Do not delete existing provider endpoints or standard zones as an
automatic rollback.

## References

- https://learn.microsoft.com/azure/architecture/networking/guide/cross-tenant-secure-access-private-endpoints
- https://learn.microsoft.com/azure/private-link/private-endpoint-dns-integration
- https://learn.microsoft.com/azure/dns/private-resolver-endpoints-rulesets
- https://learn.microsoft.com/azure/storage/common/storage-private-endpoints
- https://learn.microsoft.com/azure/azure-sql/database/private-endpoint-overview?view=azuresql
