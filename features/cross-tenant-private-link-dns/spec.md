# Cross-tenant Private Link DNS example

## Goal

Provide a public, client-agnostic Terraform example for a consumer network that
needs private access to Azure Storage Data Lake Storage Gen2 and Azure SQL
resources owned in another tenant or subscription.

## Outcomes

- Consumer-local `dfs`, `blob`, and `sql` Private DNS zones can be created or
  supplied as existing linked zone IDs.
- Cross-tenant `dfs`, `blob`, and `sqlServer` Private Endpoint requests are
  created by full provider resource ID and remain pending for provider approval.
- An optional Azure DNS Private Resolver uses a static inbound endpoint when an
  address is supplied and forwards only enterprise-owned namespaces outbound.
- The example contains no customer, tenant, subscription, resource, or network
  identifiers beyond obvious placeholders.
- Every file has a stable public link suitable for a customer implementation
  playbook.
- Pull requests changing the example run format, Checkov, backend-free init,
  and validate checks.

## Design

- Use Terraform MCP catalog modules `avm-res-network-privatednszone` `0.5.0`
  and `avm-res-network-dnsresolver` `0.8.0`.
- Document but do not use `avm-res-network-privateendpoint` `0.2.0` because it
  hardcodes automatic approval. Use raw AzureRM only for the manual cross-tenant
  connection boundary.
- Keep enterprise DNS product configuration outside Terraform. The example
  defines the Azure-side resolution contexts and rejects Azure service zones in
  resolver outbound rules.
- Do not deploy or plan against a live subscription as part of template
  validation.
- Preserve static deployment provenance on AVM-managed resources while opting
  them out of the external `LastApplied` stamp that their module lifecycle
  cannot ignore.

## Validation

- `terraform fmt -check -recursive`
- `terraform init -backend=false -input=false`
- `terraform validate -no-color`
- `terraform test -no-color` with mock providers
- client-identity leak scan
- Terraform review and PR council before merge
