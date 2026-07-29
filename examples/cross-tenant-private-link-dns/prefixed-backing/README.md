# Prefixed Private DNS backing zones

This standalone Terraform root implements custom tenant- or region-prefixed
Azure Private DNS backing zones for selected cross-tenant Private Endpoints.
Copy this directory by itself when this is the selected client architecture.

The option has no dependency on the standard-contexts implementation and no
architecture mode selector. Terraform owns custom backing-zone A records.
Enterprise DNS separately owns the exact bridge from each standard
`privatelink` target to a prefixed name or selected endpoint.

## Contract

- Applications keep normal Azure service FQDNs.
- Cross-tenant Private Endpoints are created in the consumer network with
  `is_manual_connection = true` and require provider approval.
- ADLS Gen2 includes both `dfs` and `blob` endpoints and backing records.
- Private Endpoints do not attach standard Private DNS zone groups.
- DNS publication is a separate phase after live Azure approval is verified.
- Wildcard capture of `*.privatelink.*` is outside this Terraform option.
- DNS health selection does not prove data currency, write role, authorization,
  or application transaction health.

## Two-phase deployment

1. Set `publish_dns_records = false` and apply only the pending Private Endpoint
   requests through the protected pipeline.
2. The provider validates and approves every connection.
3. Query Azure for live `Approved` state and retain the evidence.
4. Populate `approved_private_endpoint_target_keys`, set
   `publish_dns_records = true`, and apply the backing zones and records.
5. Configure and test the exact standard-name bridge in enterprise DNS.

The approved-key set is a pipeline gate, not independent proof of approval.

## Enterprise DNS bridge and health policy

Azure public DNS continues to direct normal service names to the standard
`privatelink` target. A prefixed backing zone is not queried automatically.
Create an exact CNAME, response-policy record, or health-aware synthesized
response for each approved resource. Do not use wildcard capture.

If health-aware selection is required, document every eligible endpoint,
monitor path, selection priority or topology, TTL, persistence, and
all-targets-down behavior. TCP 443 for Storage and TCP 1433 for SQL prove only
reachability. They do not prove authorization, data currency, read/write role,
or application transaction health.

## Validate and roll back

Prove the normal service FQDN reaches the exact standard-name bridge and the
expected prefixed record. Replace a pilot endpoint and require a reviewed
Terraform record update. Test monitor-path-only failure, client-path-only
failure, endpoint failure with a live NIC, all-targets-down, positive and
negative cache expiry, failover, and failback.

Expand only after two repeatable failover and failback drills meet the recovery
target, no unrelated names change, and authenticated transactions pass against
every endpoint DNS can select. Roll back the exact bridge or health policy
first and restore the prior enterprise DNS export. Preserve existing Private
Endpoints and standard zones.

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

- https://learn.microsoft.com/azure/private-link/private-endpoint-dns
- https://learn.microsoft.com/azure/architecture/networking/guide/cross-tenant-secure-access-private-endpoints
- https://learn.microsoft.com/azure/storage/common/storage-private-endpoints
- https://learn.microsoft.com/azure/azure-sql/database/private-endpoint-overview?view=azuresql
- https://learn.microsoft.com/azure/well-architected/reliability/principles
