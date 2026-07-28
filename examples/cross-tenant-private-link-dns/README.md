# Cross-tenant Private Link DNS starter

This client-agnostic example creates consumer-local Private Endpoints and
Private DNS for Azure Storage Data Lake Storage Gen2 and Azure SQL resources in
another tenant or subscription. It optionally deploys an Azure DNS Private
Resolver for a distinct consumer DNS context.

## Design contract

- Keep one enterprise DNS control plane if required, but preserve separate
  resolution contexts for each consumer network.
- Forward the public service zones (`dfs.core.windows.net`,
  `blob.core.windows.net`, and `database.windows.net`) from enterprise DNS to
  the appropriate consumer resolver. Do not forward one tenant's complete
  `privatelink.*` zones to every client.
- Create consumer-local Private Endpoints by full provider resource ID. The
  provider independently approves each pending connection.
- ADLS Gen2 requires both `dfs` and `blob` endpoints and zones.
- Applications keep using normal service FQDNs. Azure SQL clients use
  `<server>.database.windows.net`, never a raw private IP or the
  `privatelink` FQDN.
- Resolver outbound rules are only for enterprise-owned namespaces that Azure
  must resolve through central DNS.

## Terraform MCP and AVM sources

The template uses current Terraform MCP catalog examples and pins:

- [Private DNS Zone AVM 0.5.0](https://github.com/Azure/terraform-azurerm-avm-res-network-privatednszone)
- [DNS Resolver AVM 0.8.0](https://github.com/Azure/terraform-azurerm-avm-res-network-dnsresolver)
- [Private Endpoint AVM 0.2.0](https://github.com/Azure/terraform-azurerm-avm-res-network-privateendpoint)

The Private Endpoint AVM currently hardcodes automatic approval. Cross-tenant
consumers normally require `is_manual_connection = true`, so
`cross_tenant_private_endpoints.tf` is a documented direct AzureRM exception
based on the provider schema returned by Terraform MCP.

## Use

```bash
cp terraform.tfvars.example terraform.tfvars
# Replace every placeholder and remove optional resolver values not in scope.
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate
terraform plan -input=false -out=tfplan
terraform show -json tfplan > tfplan.json
```

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
4. The consumer verifies local zone records, resolver context, routes, NSGs,
   firewalls, and service authorization.
5. Enterprise DNS forwards each public service zone to the correct consumer
   resolver context.

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

Hold if the provider resource IDs, DNS context, source ranges, route, firewall,
or approval owner are unknown. Roll back the new enterprise forwarding context
or records first; do not delete existing provider endpoints or zones as an
automatic rollback.

## References

- https://learn.microsoft.com/azure/architecture/networking/guide/cross-tenant-secure-access-private-endpoints
- https://learn.microsoft.com/azure/private-link/private-endpoint-dns-integration
- https://learn.microsoft.com/azure/dns/private-resolver-endpoints-rulesets
- https://learn.microsoft.com/azure/storage/common/storage-private-endpoints
- https://learn.microsoft.com/azure/azure-sql/database/private-endpoint-overview?view=azuresql
