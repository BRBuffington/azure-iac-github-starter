# Standard-zone resolution contexts

This standalone Terraform root implements Azure Private Link DNS with separate
enterprise DNS resolution contexts and Microsoft's standard Private DNS zones.
Copy this directory by itself when this is the selected client architecture.

The option has no dependency on the prefixed-backing implementation and no
architecture mode selector. Private Endpoint zone groups own standard-record
lifecycle. Enterprise DNS forwards the public Azure service zones to static,
same-authority Azure DNS Private Resolver inbound endpoints.

## Contract

- Applications keep normal Azure service FQDNs.
- Cross-tenant Private Endpoints are created in the consumer network with
  `is_manual_connection = true` and require provider approval.
- ADLS Gen2 includes both `dfs` and `blob` endpoints and zones.
- Each Private Endpoint attaches exactly one standard Private DNS zone group.
- Every enterprise forwarding target in one client context serves the same
  answer authority.
- Terraform and enterprise DNS do not create duplicate A records for records
  owned by the zone group.

## Implementation sequence

1. Replace every placeholder in `terraform.tfvars.example`.
2. Set `provider_storage_account_id`, `provider_sql_server_id`, or both. The
  Storage ID composes both required `dfs` and `blob` targets locally; the SQL
  ID composes the `sqlServer` target.
3. Leave each `existing_*_private_dns_zone_id` null to create that standard
  zone, or set the exact existing zone ID when it is already linked to the
  consumer VNet.
4. Run a reviewed plan and create pending consumer-local Private Endpoint
  requests.
5. The provider validates and approves each connection.
6. Verify the zone group created the expected standard-zone A records.
7. Configure each enterprise DNS client context to forward
  `dfs.core.windows.net`, `blob.core.windows.net`, and
  `database.windows.net` to static, same-authority Resolver inbound endpoints.
8. Canary one client population before broader rollout.

`z_locals.tf` owns the endpoint, standard-zone, and forwarding-rule maps. The
tfvars file intentionally contains no nested resource schema.

Never put resolver endpoints for different tenant authorities in one target
list. NXDOMAIN is an authoritative answer, not a trigger to try another tenant.

## Validate and roll back

From every representative client population, capture the CNAME chain, private
A answer, TTL, responding DNS server, NXDOMAIN behavior, and timeout behavior.
Validate TCP 443 to both Storage endpoints, the selected Azure SQL connection
policy, authenticated DFS and Blob operations, and a SQL login using the normal
server FQDN.

Hold if client populations cannot be classified, resolver addresses are not
lifecycle-managed, or one forwarding rule mixes authorities. Roll back the new
enterprise DNS context or forwarding rule first. Preserve existing Private
Endpoints and zones while the failure is investigated.

## Validate

```bash
cp terraform.tfvars.example terraform.tfvars
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate -no-color
terraform test -no-color
```

Use the repository's protected plan and apply workflows for deployment. Do not
apply the example locally.

## References

- https://learn.microsoft.com/azure/private-link/private-endpoint-dns-integration
- https://learn.microsoft.com/azure/architecture/networking/guide/cross-tenant-secure-access-private-endpoints
- https://learn.microsoft.com/azure/dns/private-resolver-endpoints-rulesets
- https://learn.microsoft.com/azure/storage/common/storage-private-endpoints
- https://learn.microsoft.com/azure/azure-sql/database/private-endpoint-overview?view=azuresql