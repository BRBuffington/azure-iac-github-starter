# Sample networks

A disposable scaffold that stands up the networks the parent
[`hub-canonical-zones/`](../) root expects. It exists so the option can be
exercised end to end without an existing landing zone.

**This is a lab, not part of the option's contract.** The parent root
deliberately consumes existing network IDs, because a real deployment attaches
to a customer's landing zone rather than creating one.

## What it creates

- `rg-<prefix>-hub`, `rg-<prefix>-spoke`, `rg-<prefix>-dns`
- A hub virtual network with two subnets:
  - `snet-dnsr-inbound`, delegated to `Microsoft.Network/dnsResolvers`
  - `snet-workload`
- A spoke virtual network with `snet-workload`

The DNS resource group is separate from the network resource group so zone
ownership and network ownership can be delegated to different teams, which is
usually how a shared hub is actually run.

## The delegation matters

The inbound subnet must be **empty and delegated** to
`Microsoft.Network/dnsResolvers`. Without that delegation the resolver cannot
bind an inbound endpoint, and the enterprise forwarder has no target to point
at. Azure also requires at least a `/28` for this subnet; the default `/26`
carved here leaves headroom.

## Use

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init -backend=false -input=false
terraform validate -no-color
terraform apply
```

Then feed the result straight into the parent root:

```bash
terraform output -raw parent_tfvars_snippet >> ../terraform.tfvars
```

## Simulating two tenants

This scaffold creates both networks in one subscription, which exercises the
mechanics but not the tenant boundary. To rehearse the real cross-tenant case,
apply this in one tenant, create the spoke network in the second tenant
separately, and set `spoke_virtual_networks` in the parent root to that remote
ID. The parent's `cross_tenant_tenant_id` then pins link creation to an identity
that spans both.

## Teardown

`terraform destroy`. Destroy the parent root first if it is pointing here, since
its zone links reference these networks.
