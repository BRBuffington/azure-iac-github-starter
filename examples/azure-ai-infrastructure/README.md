# Azure AI infrastructure reference

Two independent, un-applied Terraform examples for an AI workload inside an
existing Azure landing zone. The [deployment checklist](deployment-checklist.md)
contains the recommended settings and acceptance checks. It covers infrastructure,
not application agents, prompts, ingestion, Jira, SharePoint or Teams publication.

## Ownership and layout

The layout follows a supplied shared/account versus per-environment Terraform
organization pattern. The supplied artifact was documentation, not Azure HCL;
these are new sanitized examples using official Azure Verified Modules (AVM).

| Root | Would manage | Reuses / leaves with the platform owner |
| --- | --- | --- |
| [tf/azure-shared](tf/azure-shared/virtual_network.tf) | Optional workload spoke, dedicated agent subnet, private-endpoint subnet, spoke-to-hub peering, and missing subnet NSGs/agent route table | Existing network resource group, hub, DNS servers, hub-to-spoke peering, and any NSG/route IDs supplied for reuse |
| [tf/azure-ai](tf/azure-ai/foundry.tf) | Resource group, private Foundry account/project/model, dedicated Storage/Cosmos DB/Search, private endpoints, connections, runtime roles and diagnostics | Existing subnet IDs, central private DNS zones, Log Analytics workspace and identity groups |

Skip `azure-shared` when the approved network already exists. The roots do not
call each other or read each other's state. Pass the reviewed resource IDs as
inputs. Never manage the same Azure resource, private endpoint or DNS zone group
from two states. These examples do not create or move subscriptions or management
groups, assign enterprise policies, replace a firewall, or add a second hub.

## Region recommendation

For an **all-new, single-region POC with the current example**, start with
**North Central US** (`northcentralus` / `ncus`, Illinois). It has published support
for `gpt-4.1` version `2025-04-14` with regional `Standard`, private Agent Service
and the core tools, without the Search creation restriction currently published
for the Virginia regions. This is a conditional engineering recommendation, not
a customer-approved region or a successful capacity test.

**East US 2** (`eastus2` / `eus2`, Virginia) is the preferred nearer-to-Boston
alternative if an approved dedicated Search service can be reused or new-service
capacity is confirmed. It also supports more of the optional future capabilities
below. **East US** (`eastus` / `eus`, Virginia) is viable for the current core
workload when existing network/service ownership favors it, subject to the same
Search restriction. Do not move an existing environment on geography alone.

The following comparison uses Microsoft documentation read on **18 September 2026**.
"Listed" means published capability, not tenant entitlement or available capacity.

| Capability | North Central US | East US 2 | East US |
| --- | --- | --- | --- |
| `gpt-4.1` `2025-04-14`, regional `Standard` | Listed | Listed | Listed |
| Agents/private VNet | Listed | Listed | Listed |
| Agent Service AI Search, Code Interpreter, File Search and MCP tools | Listed | Listed | Listed |
| New dedicated Search service | Listed, no creation-restriction footnote; check actual tier capacity | Current demand notice prevents new-service creation | Current demand notice prevents new-service creation |
| Regional `text-embedding-3-small` / `text-embedding-3-large` | Not listed | Both listed | Both listed |
| Agent Service Function tool / Computer Use | Neither listed | Both listed | Function listed; Computer Use not listed |
| Search availability zones | Not listed | Listed | Listed |
| Cosmos DB for NoSQL, single-region continuous backup | Supported pattern | Supported pattern | Supported pattern |

Sources: [Foundry regions/tools](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/limits-quotas-regions),
[exact model/deployment matrix](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability),
[Search regions and capacity footnotes](https://learn.microsoft.com/en-us/azure/search/search-region-support),
[Cosmos NoSQL region support](https://learn.microsoft.com/en-us/azure/cosmos-db/tutorial-global-distribution)
and [continuous backup](https://learn.microsoft.com/en-us/azure/cosmos-db/continuous-backup-restore-introduction).

### Capability limits that change the recommendation

- North Central US is not a like-for-like fallback if regional `text-embedding-3`,
  the Agent Service Function tool, Computer Use or zonal Search becomes required.
  The Function entry concerns the Agent Service tool, not the availability of the
  Azure Functions service. GPT-4.1 itself does not support Computer Use in any
  region; that tool also needs a compatible model. Do not silently choose another
  embedding model or processing geography to make a region fit.
- [Basic Search supports inbound private endpoints](https://learn.microsoft.com/en-us/azure/search/search-sku-tier),
  but private indexers that use skillsets require S2 or higher. A region with
  Search or agentic retrieval does not remove that tier requirement. This example
  provisions runtime Search, not an application ingestion pipeline.
- Standard StorageV2 supports [LRS](https://learn.microsoft.com/en-us/azure/storage/common/storage-redundancy).
  Cosmos NoSQL is documented across Azure regions, with continuous backups in
  each configured account region. Keep these stores alongside the workload where
  practical; LRS and a single Cosmos region are POC choices, not zonal/regional HA.
  Actual create access and regional capacity have not been tested for the customer.
- [Private-BYO restrictions](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks)
  still apply: uploading Blob files alone does not provide File Search, and Code
  Interpreter file handling has an SDK/container requirement. Regional tool
  availability does not prove a proposed private data path works.
- Regional `Standard` processes inference in the deployment region;
  `DataZoneStandard` and `GlobalStandard` have different processing boundaries.
  Do not substitute either without approval. Canada is not selected merely for
  proximity: residency and the exact model/deployment combination must fit.

The remaining customer checks are actual quota/tier capacity, allowed locations,
residency, the existing VNet's region and measured latency from the approved
network. Virginia and Illinois are location facts, not latency measurements.
Foundry and its agent VNet must share a region. Leave deployment inputs and policy
parameters as customer choices; the `eastus` values in the sanitized tfvars files
are examples, not an unconditional recommendation for a new Search deployment.

## Reference settings

| Area | Explicit starting configuration |
| --- | --- |
| Network | Dedicated agent subnet, `/24` recommended; separate endpoint subnet; no default outbound access; explicit NSG allow/deny rules and `0.0.0.0/0` to the existing firewall, or supplied NSG/route IDs |
| Foundry | Standard private infrastructure; public access disabled; local authentication disabled; system-assigned identities |
| Runtime stores | Private endpoints; key/local authentication disabled; no trusted-service bypass or public IP exceptions |
| POC availability | Storage LRS; Cosmos DB one explicitly selected region; Search Basic, one partition and one replica; no production availability claim |
| Model | Explicit model/version and capacity; regional `Standard` deployment; `NoAutoUpgrade` requires an owner to track model retirement |
| Access | Builders: project Foundry User and account Reader; consumers: project Foundry Agent Consumer; stable group IDs, never the current applier |
| Diagnostics | `AllMetrics` plus Foundry `Audit`, Cosmos `ControlPlaneRequests`, Search `OperationLogs`, and Blob read/write/delete logs to the existing workspace; no `allLogs`, Foundry `RequestResponse` or `Trace` by default |

The POC sizing is a reference starting point, not a measured requirement or a
production recommendation. Confirm model/region availability, quotas, Search
features and Cosmos throughput before deployment. Production redundancy, backup
and recovery targets require separate sizing; the POC recovery baseline is below.
Key Vault, customer-managed keys,
APIM, application storage and hosted-agent container infrastructure are conditional
additions, not silently provisioned dependencies.

Foundry AVM `0.11.3` owns project connections, capability hosts, managed identities
and service-specific runtime roles. Resource Group AVM is `0.4.0`; VNet AVM is
`0.22.2`. Direct `azurerm_role_assignment` is used only for project user groups,
which the pattern module does not expose as a project role-assignment input.
Review the expanded plan and role scopes; mock tests do not validate the upstream
module's live behavior or network readiness.

## Identity and subscription bootstrap

These settings belong in the platform owner's existing identity/bootstrap
configuration. The workload roots do not create tenants, subscriptions, Entra
groups, federated credentials or subscription-wide role grants.

| Item | Concrete starting configuration |
| --- | --- |
| Provider registration | For the selected private Standard setup: `Microsoft.CognitiveServices`, `Microsoft.Storage`, `Microsoft.DocumentDB`, `Microsoft.Search`, `Microsoft.Network`, `Microsoft.App`, `Microsoft.ContainerService`, `Microsoft.MachineLearningServices`, `Microsoft.KeyVault` and `Microsoft.Insights`. Register centrally; do not make a workload destroy unregister a shared provider. `Microsoft.Bing` is only for a separately selected Bing tool. |
| GitLab federation | Issuer is the actual HTTPS GitLab instance URL; audience `api://AzureADTokenExchange`; subject restricted to `project_path:<group>/<project>:ref_type:branch:<protected-branch>`. Issue an ID token only in protected deployment jobs. The issuer's discovery/JWKS endpoint must be reachable by Entra; an inaccessible internal issuer needs the existing approved identity path, not a made-up public URL. |
| Provider authentication | Supply the protected job's `ARM_CLIENT_ID`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`, `ARM_OIDC_TOKEN` and `ARM_USE_OIDC=true`. GitLab HTTP state credentials remain a separate job-scoped path. Never put tokens into HCL, tfvars or logs. |
| Plan principal | Start with Reader on the workload resource groups and referenced network/DNS/logging scopes, plus the required GitLab state access. Validate the actual module's plan reads before granting any additional operation; do not automatically make the planner a writer. |
| Apply principal | Contributor on the workload resource groups; subnet join/read rights on the specific existing subnets; Private DNS Zone Contributor on the six zones only if this root owns zone groups. Role Based Access Control Administrator is separately approved at the scopes where runtime/group roles are created. No subscription-wide Owner default. |
| Initial resource groups | The platform bootstrap creates/adopts the groups before resource-group-scoped delegation. If the AI group already exists, import it into its intended owning module/state before use; do not recreate it. Creating a new resource group is a separate subscription-level bootstrap operation, not a capability implied by an existing group's Contributor grant. |
| Builder/consumer groups | Pass stable object IDs in `builder_group_ids` and `consumer_group_ids`. The AI root grants project Foundry User plus account Reader to builders, and project Foundry Agent Consumer to consumers. Empty lists create no grants. |

### Runtime roles already created by the AVM

The pinned Foundry AVM `0.11.3` assigns these to the **project system-assigned
managed identity**. Inspect the expanded plan instead of assigning them again.

| Role | Scope / qualification |
| --- | --- |
| Storage Blob Data Contributor | Dedicated runtime Storage account |
| Storage Blob Data Owner | Same account, with the module's ABAC condition on blob-tag/filter operations; this is not blanket container isolation of every blob operation |
| Cosmos DB Operator | Dedicated runtime Cosmos account, Azure control plane |
| Cosmos DB Built-in Data Contributor | NoSQL data plane at `/dbs/enterprise_memory`; role suffix `00000000-0000-0000-0000-000000000002` |
| Search Service Contributor and Search Index Data Contributor | Dedicated runtime Search service |

The broader account-level grants are why these stores are dedicated to the
workload. They do not authorize access to unrelated application or export stores.
The module adds some data-plane grants after capability-host creation; allow its
dependency graph to run rather than duplicating those grants as a prerequisite.
If narrower grants are required, review the module's supported behavior with the
identity owner instead of representing this reference as already narrowly scoped
to individual containers or indexes.

## Diagnostics and operating defaults

The AI root now configures the following diagnostic settings, not just metrics.
The values are explicit in `terraform.tfvars.example` and can be overridden with
`foundry_log_categories` and `runtime_log_categories`.

| Target | Log categories | Destination table / mode |
| --- | --- | --- |
| Foundry account | `Audit` | `AzureDiagnostics` |
| Cosmos DB account | `ControlPlaneRequests` | `CDBControlPlaneRequests` / `Dedicated` |
| Search service | `OperationLogs` | `AzureDiagnostics` |
| Storage account | Metrics only at this scope | `AzureMetrics` |
| Storage `/blobServices/default` | `StorageRead`, `StorageWrite`, `StorageDelete` | `StorageBlobLogs` / `Dedicated` |

[diagnostics.tf](tf/azure-ai/diagnostics.tf) owns only the Blob diagnostic setting.
It uses the provider resource because Foundry AVM `0.11.3` does not expose the
Storage subservice diagnostic input. The other settings use the existing AVM
interfaces. An empty Blob category set omits that diagnostic resource; empty
service category sets retain metrics without enabling those logs.

Operation and audit logs can still contain identities, resource/blob paths and
query terms. Excluding request/response capture does **not** make them PHI-free.
Approve the destination, payload and access before using real data. Additional
Foundry `RequestResponse`/`Trace` and Cosmos query/partition-key categories are
not part of this baseline.

| Platform-owner action | Recommended starting setting and evidence |
| --- | --- |
| Log retention | For POC logs, start with 30 days of Analytics retention, subject to security/legal requirements and the existing retention policy. Retain any longer required total retention. Do not shorten shared `AzureDiagnostics` or workspace retention for this workload; table settings affect other contributors too. Read back the effective table retention and reader permissions. |
| Subscription Activity Log | Reuse the central export. If absent, the platform owner forwards `Administrative`, `Security`, `Policy`, `ServiceHealth` and `ResourceHealth` categories to the approved workspace; this is separate from service resource logs. |
| Budget | Create a `Monthly` budget at the AI resource-group scope using the approved amount and billing currency. Start with `Actual` notifications at 80% and 100%, plus `Forecasted` at 100%, sent to the workload and platform cost owners. Choose start/end dates explicitly. Shared hub/logging charges need their own existing allocation; they are not all in this resource-group budget. |
| Alert response | At 80%, inspect model executions, Search allocation, Cosmos RU consumption and log ingestion. At 100% or forecast breach, the named owner decides whether to pause the POC. Budget alerts do not cap spending or stop resources and are not real-time. Do not add automatic shutdown of shared services. |

Budgets, central Activity Log export and workspace retention belong in their
existing platform Terraform, not this workload state. Their amounts, addresses,
retention exceptions and dates are customer inputs, not inferred values.

### Recovery and module limits

| Resource | Concrete POC baseline | Current example coverage |
| --- | --- | --- |
| Blob runtime files | Recommend blob and container soft delete for 7 days, with versioning; reconcile retained versions with data-deletion obligations. Keep an approved test object for a restore exercise. | **Not configured.** Foundry `0.11.3` does not pass `blob_properties` to Storage AVM `0.6.9`; its default is `null`. Do not assume that the nested object's 7-day defaults are active. Adopt these properties in the owning supported Storage composition before claiming file recovery. |
| Cosmos runtime history | Keep continuous 30-day point-in-time backup as this reference's recovery baseline; identify a restore operator and test into a separate destination. | The nested Cosmos AVM `0.10.0` defaults to `Continuous` / `Continuous30Days`. The Foundry pattern does not forward its `backup` input. A different backup policy needs a supported owning composition, not an ignored tfvars value. Verify the plan and deployed backup policy. |
| Search runtime vectors | A single Basic replica is a POC starting point, not HA or backup. Preserve source/configuration needed to reconstruct indexes and prove a rebuild before relying on it. | No snapshot/restore mechanism is implemented by this root; generated runtime state requires a service-supported recovery test. |
| Terraform state | Retain GitLab version history and an independently recoverable state backup; use the owning team's authorized recovery process with deployments paused. | HTTP backend/locking contract only; these examples do not back up the GitLab service. Never create a new empty state to recover an existing deployment. |

These are specific adoption items, not production recovery guarantees. Do not
modify downloaded `.terraform/modules` files or let a second state manage the
same account to compensate for a missing module input.

## Network defaults

[network_security.tf](tf/azure-shared/network_security.tf) creates the missing
controls with NSG AVM `0.5.1` and Route Table AVM `0.5.0`. Their complete rule maps
are in [z_locals.tf](tf/azure-shared/z_locals.tf). A non-null existing NSG or route
ID skips creation of that control and uses it unchanged; the rules below are not
applied to a reused resource. Null IDs in the sample select creation. Replace the
sample client CIDRs, DNS IPs and firewall IP with the approved values.

| NSG / direction | Priority | Source -> destination | Protocol / destination ports |
| --- | --- | --- | --- |
| Agent inbound | 100 | Agent subnet -> itself | Any; preserves managed-runtime internal communication |
| Agent inbound | 110 | `AzureLoadBalancer` -> agent subnet | TCP `30000-32767` platform probes |
| Agent outbound | 100 / 110 | Agent subnet -> `dns_server_ips` | UDP / TCP `53` |
| Agent outbound | 120 | Agent subnet -> private-endpoint subnet | TCP `443` |
| Agent outbound | 130, when configured | Agent subnet -> `cosmos_direct_endpoint_ips` | TCP `0-65535` for Cosmos Direct mode only |
| Agent outbound | 140 | Agent subnet -> itself | Any |
| Agent outbound | 200 / 210 / 220 / 230 | Agent subnet -> `AzureActiveDirectory` / `MicrosoftContainerRegistry` / `AzureFrontDoor.FirstParty` / `AzureMonitor` | TCP `443` |
| Endpoint inbound | 100 | Agent subnet + `approved_client_cidrs` -> endpoint subnet | TCP `443` |
| Endpoint inbound | 130, when configured | Agent subnet -> `cosmos_direct_endpoint_ips` | TCP `0-65535` |
| Both NSGs, both directions | 4096 | Everything else | Deny; replies to allowed connections are stateful |

These are a starting rule set for the private Standard infrastructure, not a
guarantee for every hosted-agent/tool combination. The platform HTTPS tags preserve
the documented managed-identity, system-container and monitoring dependencies;
they do not permit arbitrary Internet egress. The existing firewall must also
allow the corresponding required destinations without unsupported TLS inspection.
Do not explicitly block the platform DNS service `168.63.129.16`; its platform
traffic is not governed like ordinary custom-DNS traffic. Extra tools or image
sources need their own documented allows before the deny rules are adopted.

The baseline permits HTTPS to the private stores. Cosmos Direct mode additionally
requires **all** Cosmos private-endpoint addresses, including its global and regional
addresses, in `cosmos_direct_endpoint_ips`. Both NSGs then allow the documented TCP
`0-65535` range to only those addresses from the agent subnet. Empty means no Direct
mode exception, not verified Direct-mode connectivity. Populate these addresses
before testing a runtime that requires it; do not open all ports to the endpoint
subnet or the Internet as a substitute.

The created route table uses `0.0.0.0/0 -> VirtualAppliance -> firewall_private_ip`
and disables BGP propagation. It is associated with the **agent** subnet, not the
private-endpoint subnet. More-specific VNet/peering routes still take precedence;
this is default egress routing, not forced inspection of all east-west traffic.
If the existing hybrid design needs gateway-learned routes, supply its reviewed
route table or adapt this setting with the network owner. Peering enables VNet
access and forwarded traffic, leaves gateway transit off, and does not create the
reverse peering. The hub owner completes that reverse peering and return path.

### DNS forwarding

[dns-forwarders.example.json](dns-forwarders.example.json) provides the six concrete
public-zone conditional forwarders and their corresponding private zones. It is a
configuration handoff for the existing DNS owner, not a template loaded by Terraform.
Configure these forwards on enterprise/on-premises DNS to the existing Azure DNS
Private Resolver **inbound** endpoint IPs (or Azure-hosted DNS forwarders). Allow
UDP and TCP `53` across that path. Do not point on-premises DNS directly at
`168.63.129.16`, or forward a resolver back to itself.

Link each corresponding `privatelink.*` zone to the VNet containing the Azure
resolver, with auto-registration disabled. Set the spoke's `dns_server_ips` to the
reachable approved resolvers. Forward the **public** suffixes in the JSON, not only
the `privatelink.*` suffixes. VNet peering alone does not make private DNS links
transitive. Keep one owner for each zone, link and endpoint zone group; this root
does not create a new resolver, firewall or duplicate platform DNS zones.

## State and deployment

Each root uses an empty Terraform `http` backend for adoption into the existing
internal GitLab state service. This is a bounded example-specific backend choice;
the starter's Azure Storage backend and GitHub deployment workflows are unchanged.

- Use one GitLab state name per layer and environment, for example
  `network-eus-dev` and `ai-eus-dev`. Never combine that separation with workspaces.
- Supply `TF_HTTP_ADDRESS`, `TF_HTTP_LOCK_ADDRESS`, `TF_HTTP_UNLOCK_ADDRESS`,
  `TF_HTTP_LOCK_METHOD=POST` and `TF_HTTP_UNLOCK_METHOD=DELETE` in the adopting
  pipeline. Use HTTPS and the normal trusted certificate chain.
- For GitLab, the address shape is
  `https://<gitlab-host>/api/v4/projects/<project-id>/terraform/state/<state-name>`;
  the lock and unlock address is that same URL plus `/lock`.
  Use `TF_HTTP_RETRY_WAIT_MIN=5` as a starting retry interval. Serialize jobs by
  the **state name** so two roots cannot apply to the same state concurrently.
- Supply `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` from the existing approved
  GitLab job-token/credential path. Do not put them in HCL, tfvars, backend files,
  command arguments or saved-plan logs. Backend authentication is separate from
  the Azure provider's Entra/OIDC authentication.
- Retain GitLab state access controls, locking, protected deployment approvals,
  serialized applies and an independently recoverable state backup.
- Copy a sanitized `terraform.tfvars.example` into a private config named
  `<scope>-<region>-<env>.tfvars`. Each actual environment needs its own state.
- Generate and commit dependency locks in the adopting repository. This starter
  excludes generated locks. Module-managed resources use `LastAppliedStamp=Disabled`;
  `DeployedByRepo` is supplied through the common tag map, subject to the Search
  module limitation below.
- Review the pipeline plan before an authorized apply. Stop on any unexpected
  deletion, replacement or shared-platform change. No local apply is prescribed.

Network readiness must precede capability-host provisioning: verify bidirectional
peering, dependency DNS, required firewall/NSG egress and runner reachability first.
This example owns workload private-endpoint zone groups; a platform policy must not
also manage those same groups. Use existing platform routines instead when that
ownership contract differs.

## Azure Policy JSON

The [azure-policy/README.md](azure-policy/README.md) describes a scoped initiative,
non-enforcing assignment and separate parameter JSON for the platform owner.
It references Microsoft built-ins for locations, five resource-group tags,
network restrictions, Entra authentication and Storage HTTPS/TLS. It is not the
full ALZ policy pack and is not loaded by these Terraform roots. The guide records
the built-ins' coverage limits, including where policy compliance is weaker than
the private-only settings in this example. Regions remain customer-selected.

### Tag coverage

Apply `Owner`, `CostCenter`, `Environment`, `DataClassification` and
`DeployedByRepo` to taggable workload resources, not only the resource group.
Both roots supply the common tag map, but Foundry AVM `0.11.3` omits `tags` on
its Search service resource while tagging its Search private endpoint. The
supplied initiative checks resource-group tag presence; it does not propagate
tags or remediate this omission. Configure Search tags through the platform's
approved existing tag policy or a supported owning Search composition, then
read back all five values on the service. This remains an adoption action, not
implemented Search tag coverage. Do not edit the downloaded module cache.

## Validation

Run these commands separately in each root. They need no remote state or Azure
credentials; the tests override modules and prove the authored input contracts.

```text
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate -no-color
terraform test -no-color
```

Run the repository's existing Checkov gate against this directory before merge.
After adoption, retain the actual plan and perform the checklist's live access,
DNS, policy and diagnostic checks. Formatting, validation and mock plans do not
prove deployment success, runtime access or compliance.

## References

- https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/
- https://learn.microsoft.com/azure/architecture/ai-ml/architecture/baseline-microsoft-foundry-landing-zone
- https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks
- https://learn.microsoft.com/en-us/azure/container-apps/firewall-integration
- https://learn.microsoft.com/en-us/azure/cosmos-db/how-to-configure-private-endpoints
- https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns-integration
- https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry
- https://learn.microsoft.com/en-us/azure/azure-monitor/reference/supported-logs/microsoft-cognitiveservices-accounts-logs
- https://learn.microsoft.com/en-us/azure/azure-monitor/reference/supported-logs/microsoft-documentdb-databaseaccounts-logs
- https://learn.microsoft.com/en-us/azure/azure-monitor/reference/supported-logs/microsoft-search-searchservices-logs
- https://learn.microsoft.com/en-us/azure/azure-monitor/reference/supported-logs/microsoft-storage-storageaccounts-blobservices-logs
- https://learn.microsoft.com/en-us/azure/azure-monitor/logs/data-retention-configure
- https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-acm-create-budgets
- https://registry.terraform.io/modules/Azure/avm-ptn-aiml-ai-foundry/azurerm/0.11.3
- https://docs.gitlab.com/user/infrastructure/iac/terraform_state/