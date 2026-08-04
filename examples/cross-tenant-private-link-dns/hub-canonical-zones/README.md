# Hub-hosted canonical zones

This standalone Terraform root implements Azure Private Link DNS with a single
authoritative pair of Microsoft's canonical Private DNS zones, hosted in one
elected hub and shared with every other network through resolution-only virtual
network links. Copy this directory by itself when this is the selected client
architecture.

The option has no dependency on the standard-contexts or prefixed-backing
implementations and no architecture mode selector. The hub owns the canonical
zone and its records. Enterprise DNS forwards each canonical suffix to one
inbound endpoint.

## Contract

- Applications keep normal Azure service FQDNs.
- Exactly one zone exists per Private Link suffix, in the hub.
- Every consuming network receives a resolution-only link; none register into it.
- A virtual network in another Microsoft Entra tenant may be linked. The deploying
  identity must hold write permission on the private DNS zone and on that virtual
  network, in both tenants.
- Private Endpoints owned outside the hub publish canonical A records explicitly.
- ADLS Gen2 requires both `dfs` and `blob`; selecting one without the other fails
  the guard.

## Why one zone rather than one per tenant

Azure's Private Endpoint DNS integration emits a fixed CNAME chain:

| Name | Type | Value |
|---|---|---|
| `<account>.dfs.core.windows.net` | CNAME | `<account>.privatelink.dfs.core.windows.net` |
| `<account>.privatelink.dfs.core.windows.net` | A | private endpoint IP |

The second hop always targets the canonical suffix. A prefixed variant such as
`<tenant>.privatelink.dfs.core.windows.net` is a valid Azure resource, but no
client CNAME ever points at it, so the portal, the SDKs, and the ADLS Gen2 driver
never query it. That is the failure this root avoids.

Splitting the same canonical suffix across per-tenant resolvers does not work
either. When a query does not match a private DNS zone linked to the resolver's
virtual network, the resolver falls through to public Azure DNS and returns a
**successful public answer**. Enterprise DNS receives a valid response, never
retries a second forwarder, and the client connects over the public path. Multiple
forwarders are only safe when every target serves the same complete namespace.

## Inputs that carry the design

| Input | Why it exists |
|---|---|
| `hub_virtual_network_id` | The single authority. Hosts the inbound endpoint. |
| `spoke_virtual_networks` | Networks that resolve the canonical zones, including other tenants. |
| `published_endpoint_records` | Records for endpoints the hub does not own. A link resolves; it does not register. |
| `canonical_zone_keys` | Which canonical suffixes this hub is authoritative for. |
| `cross_tenant_tenant_id` | Optional. Pins spoke link creation to an identity that spans both tenants. |

## Where the links are created, and the credential seam

Zone links are explicit `azurerm_private_dns_zone_virtual_network_link`
resources in `zone_virtual_network_links.tf`, not a nested module argument, so
each one is its own plan entry and the credential boundary is visible. You get
one link per zone per network: two canonical zones and one spoke means two hub
links and two spoke links.

A `virtualNetworkLinks` resource is a **child of the private DNS zone**, so it is
always created in the hub subscription regardless of which tenant owns the linked
network. The spoke tenant cannot create it alone. What varies is the credential:
Azure requires write permission on the zone **and** on the virtual network, in
both tenants.

The `azurerm.cross_tenant` provider alias exists for exactly that. Leave
`cross_tenant_tenant_id` null and it authenticates like the default provider,
which is correct when one identity already spans both tenants. Set it to pin link
creation to a multi-tenant service principal or a B2B guest.

If governance forbids any single identity holding rights in both tenants, this
root cannot create the spoke link at all. That is an Azure constraint, not a
Terraform one, and it is worth confirming before committing to this option.

## Trying it without a landing zone

[`sample-networks/`](sample-networks/) is a disposable scaffold that creates a hub
virtual network with a properly delegated resolver inbound subnet, a spoke
virtual network, and the resource groups this root expects. It emits a
paste-ready tfvars fragment. It is a lab, not part of this option's contract:
this root consumes existing networks on purpose, because a real deployment
attaches to a customer landing zone rather than creating one.

## Deliberate omissions

- **No forwarding ruleset.** Cross-tenant ruleset linking is not supported, so a
  ruleset here cannot reach spoke tenants and would reintroduce the per-tenant
  split this root removes.
- **No Azure Lighthouse dependency.** Azure DNS Private Resolver is documented as
  incompatible with Lighthouse. Cross-tenant access here is direct RBAC on the zone
  and the linked virtual network.
- **No autoregistration.** Private Link zones must not absorb spoke VM records.

## Operating notes

- Publishing a record is a manual contract with the owning subscription. Read the
  Private Endpoint NIC's private IP in the owning tenant and add it here, or drive
  it from that tenant's pipeline. Drift shows up as a name that silently resolves
  publicly again.
- Enterprise DNS should forward only the suffixes emitted by
  `enterprise_forwarding_domains`, and only to `dns_resolver_inbound_endpoints`.
- Keep the storage account's public network access denied once private resolution
  is proven. A Private Endpoint does not disable the public endpoint by itself.

## References

- [Azure Private DNS FAQ - cross-tenant virtual network links](https://learn.microsoft.com/en-us/azure/dns/dns-faq-private)
- [Virtual network link subresource](https://learn.microsoft.com/en-us/azure/dns/private-dns-virtual-network-links)
- [Azure Private Endpoint private DNS zone values](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)
- [Azure DNS Private Resolver overview and restrictions](https://learn.microsoft.com/en-us/azure/dns/dns-private-resolver-overview)
- [Use private endpoints for Azure Storage](https://learn.microsoft.com/en-us/azure/storage/common/storage-private-endpoints)
