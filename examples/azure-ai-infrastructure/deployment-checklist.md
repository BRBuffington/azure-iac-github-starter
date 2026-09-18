# Azure Infrastructure Deployment Checklist

Azure landing zone and private Foundry foundation | 18 September 2026

Resource-by-resource build order for a private AI POC, environment `dev`.
Deployment region: to be selected by the customer using step 0. Then substitute
the chosen region and naming alias for `<deployment-region>` and `<region-alias>`.
No deployment is claimed.

Create the resource when missing; otherwise reuse its approved resource ID.
Existing hub, firewall, central DNS and monitoring remain with their current owner.
The platform owner performs governance steps; the supplied Terraform examples cover
the optional workload spoke and the private Foundry foundation, not every step below.

## 0. Choose the deployment region

- [ ] For an all-new, single-region POC using this reference's `gpt-4.1` `2025-04-14` with regional `Standard` deployment, start with **North Central US** (`northcentralus` / `ncus`, Illinois). Published support includes the model, Agents/private VNet, AI Search, Code Interpreter, File Search and MCP. It has no new-Search capacity restriction notice, unlike the Virginia candidates; actual subscription capacity is not guaranteed.
- [ ] Prefer **East US 2** (`eastus2` / `eus2`, Virginia) for proximity to Boston and broader capability coverage if an approved dedicated Search service can be reused or new-service capacity is confirmed. **East US** (`eastus` / `eus`, Virginia) can also suit an existing network and the current core tools. Both currently carry Microsoft's new-Search creation restriction. Exclude North Central US if same-region regional `text-embedding-3`, the Agent Service Function tool, Computer Use or zonal Search is required; see the [verified capability comparison](README.md#region-recommendation).
- [ ] Select the region after confirming actual quota/capacity, allowed-location policy, data residency and measured network latency. Keep Foundry and its agent VNet together and use the selected region/alias consistently in Terraform and policy parameters. Basic Search supports inbound Private Link, not private skillset indexers (S2 or higher is required). Do not silently change regional `Standard` to `GlobalStandard`/`DataZoneStandard` to obtain a model.

Recommendations checked against Microsoft documentation on **18 September 2026**,
not a customer region selection or live capacity test. StorageV2/LRS and single-region
Cosmos DB for NoSQL with continuous backup remain the POC backing-store pattern;
they do not provide regional failover. No Boston-network latency has been measured.

## 1. Subscription and governance

- [ ] Create the AI POC management group beneath the approved parent; leave existing platform and clinical subscriptions in place.
- [ ] Create or reuse the POC policy set using [azure-policy/initiative.json](azure-policy/initiative.json): approved locations, five resource-group tags, network restrictions, supported Entra-only service controls and Storage HTTPS/TLS. Review the [built-in coverage limits](azure-policy/README.md#coverage-limits); do not duplicate inherited controls.
- [ ] Assign the policy set to the POC management group using [azure-policy/assignment.example.json](azure-policy/assignment.example.json), with its `properties.parameters` populated from [azure-policy/parameters.example.json](azure-policy/parameters.example.json). Replace scope/region placeholders and start in `DoNotEnforce` while checking inherited-policy conflicts; do not disable existing assignments.
- [ ] Associate the selected unused or pre-provisioned subscription with the approved POC management group. This changes governance placement, not its billing ownership.
- [ ] Enable enforcement on the new assignment after its policy checks pass and the platform owner approves. The supplied Audit/Deny controls need no remediation identity; any separately approved remediation policies need their own identity and scoped roles.

## 2. Resource groups and deployment identity

- [ ] Deploy the network resource group in `<deployment-region>`, for example `rg-aidemo-<region-alias>-dev-network`, if an approved network resource group does not already exist.
- [ ] Deploy the AI workload resource group in `<deployment-region>`: `rg-aidemo-<region-alias>-dev-ai`. Apply `Owner`, `CostCenter`, `Environment`, `DataClassification` and `DeployedByRepo` tags.
- [ ] Register the [listed resource providers](README.md#identity-and-subscription-bootstrap) centrally for the selected private Standard setup, including `Microsoft.DocumentDB` for Cosmos DB and `Microsoft.Insights` for diagnostics. Register `Microsoft.Bing` only if that tool is selected; keep registration outside workload teardown.
- [ ] Create or reuse separate plan/apply identities using the [bootstrap settings](README.md#identity-and-subscription-bootstrap): actual GitLab HTTPS issuer, audience `api://AzureADTokenExchange`, protected-project/branch subject, Reader for plan and workload-resource-group Contributor for apply. Scope subnet/DNS access to the referenced resources and authorize role-assignment rights separately; bootstrap new resource groups before resource-group-scoped delegation.

## 3. Virtual network and subnets

- [ ] Deploy the workload VNet in `<deployment-region>`, for example `vnet-aidemo-<region-alias>-dev`, using an approved non-overlapping RFC1918 address space. Skip this resource when reusing an existing spoke.
- [ ] Create `snet-agents`: dedicated to one Foundry account, `/24` recommended, delegated to `Microsoft.App/environments`, with default outbound access disabled.
- [ ] Create `snet-private-endpoints`: separate from the agent subnet, with default outbound access disabled and NSG policies enabled for private endpoints.
- [ ] Create or reuse the two subnet NSGs using the [network rule table](README.md#network-defaults). Agent outbound: priorities `100/110`, UDP/TCP `53` to approved DNS; priority `120`, TCP `443` to the private-endpoint subnet; priorities `200/210/220/230`, TCP `443` to `AzureActiveDirectory`, `MicrosoftContainerRegistry`, `AzureFrontDoor.FirstParty` and `AzureMonitor`, respectively. Endpoint inbound: priority `100`, TCP `443` from the agent subnet and approved runner/admin CIDRs only. Deny other traffic at priority `4096` in both directions. Existing IDs reuse the controls unchanged rather than reassign their ownership.
- [ ] Preserve managed-runtime communication in the agent NSG: priority `100` inbound and `140` outbound allow traffic within the agent subnet; priority `110` inbound permits `AzureLoadBalancer` TCP `30000-32767` probes. Do not explicitly block platform DNS `168.63.129.16`. Add any selected tool/image dependencies before adopting the deny rules; this baseline does not enable arbitrary application ingress or Internet access.
- [ ] If Cosmos Direct mode is used, populate `cosmos_direct_endpoint_ips` with all global/regional Cosmos private-endpoint addresses. Add the matching agent-outbound and endpoint-inbound TCP `0-65535` rules to those addresses only; HTTPS-only rules do not prove Direct-mode connectivity.
- [ ] Create or reuse the agent egress route table and associate it with `snet-agents`. The reference creates `0.0.0.0/0`, next hop `VirtualAppliance`, using `firewall_private_ip`, with BGP propagation disabled. Keep more-specific private paths and return routing intact; reuse the reviewed table if the hybrid design needs gateway-learned routes. Configure matching required destinations on the existing firewall without unsupported TLS inspection.
- [ ] Create spoke-to-hub peering with VNet access and forwarded traffic enabled, then have the hub owner create the reverse peering. Leave gateway transit and remote-gateway use off unless the existing gateway design requires them.
- [ ] Configure the VNet's `dns_server_ips` and the six public-zone conditional forwarders in [dns-forwarders.example.json](dns-forwarders.example.json): `cognitiveservices.azure.com`, `openai.azure.com`, `services.ai.azure.com`, `blob.core.windows.net`, `documents.azure.com`, and `search.windows.net`. Forward enterprise DNS to the existing Azure resolver inbound IPs over UDP/TCP `53`, not directly to `168.63.129.16`. Retain the existing hub, resolver and firewall.

## 4. Foundry and runtime stores

- [ ] Deploy the dedicated runtime Storage account: StorageV2, Standard/LRS for the POC, minimum TLS 1.2, public access disabled and shared-key authentication disabled.
- [ ] Configure 7-day blob/container soft delete and versioning in the owning Storage configuration, subject to data-deletion requirements. These are [recommended recovery settings](README.md#recovery-and-module-limits), not settings currently exposed by the Foundry pattern; do not add an ignored module input or a second state owner.
- [ ] Deploy the dedicated runtime Cosmos DB account: NoSQL, Session consistency, one region for the POC, public access disabled and local authentication disabled; no public-IP or trusted-service bypass.
- [ ] Retain the example's Cosmos continuous 30-day backup and validate a restore to a separate destination. The pattern's `backup` input is not forwarded; a different approved recovery policy needs a supported owning composition. One region and continuous backup do not provide regional failover.
- [ ] Deploy the dedicated runtime AI Search service: Basic, one partition and one replica as a small-POC starting point; public access and local authentication disabled.
- [ ] Deploy the Foundry account: S0, Standard private setup, system-assigned managed identity, local authentication disabled, public access disabled and network ACL default `Deny`. Configure injection into `snet-agents`; account and VNet must share a region.

## 5. Private endpoints and DNS

- [ ] Create the Foundry private endpoint in `snet-private-endpoints`, targeting subresource `account`.
- [ ] Create the Storage private endpoint targeting `blob`, the Cosmos DB endpoint targeting `Sql`, and the Search endpoint targeting `searchService`.
- [ ] Create any missing central private DNS zones: `privatelink.cognitiveservices.azure.com`, `privatelink.openai.azure.com`, `privatelink.services.ai.azure.com`, `privatelink.blob.core.windows.net`, `privatelink.documents.azure.com` and `privatelink.search.windows.net`.
- [ ] Link the six private zones to the Azure resolver VNet with auto-registration disabled; peering does not make DNS links transitive. Attach the corresponding DNS zone groups to each private endpoint; assign either Terraform or policy ownership, not both. Do not create a forwarding loop back to the same resolver.
- [ ] Resolve each service hostname from the approved runner and administrator network before provisioning the capability host; the result must use the intended private endpoint.

## 6. Foundry project and access

- [ ] Create the Foundry project and its system-assigned managed identity in the workload account.
- [ ] Assign the project managed identity the [AVM runtime roles](README.md#runtime-roles-already-created-by-the-avm): Storage Blob Data Contributor/conditional Data Owner, Cosmos DB Operator plus NoSQL Data Contributor on `enterprise_memory`, and Search Service Contributor/Index Data Contributor. The pinned module creates these grants in dependency order; do not assign duplicates or treat its account-wide grants as container-level isolation.
- [ ] Create the three Entra-authenticated project connections for runtime file storage, thread storage and vector storage.
- [ ] Create the project Agents capability host after the connections, role assignments and private DNS are ready. This provisions infrastructure, not an application agent.
- [ ] Deploy the selected model with an explicit name, version and quota capacity. Use regional `Standard` where supported and approved; if `NoAutoUpgrade` is used, assign an owner for model retirement and upgrades.
- [ ] Create or reuse builder and consumer Entra groups. Assign builders project-scoped Foundry User plus account Reader; assign endpoint-only consumers project-scoped Foundry Agent Consumer.

## 7. Diagnostics and final deployment checks

- [ ] Create the [implemented diagnostic settings](README.md#diagnostics-and-operating-defaults): Foundry `Audit`, Cosmos `ControlPlaneRequests`, Search `OperationLogs`, and Blob `StorageRead`/`StorageWrite`/`StorageDelete` at `/blobServices/default`, plus account/service metrics. Exclude `RequestResponse`, `Trace` and `allLogs` by default. Approve log payloads and readers; operation logs can still contain sensitive identifiers or query terms.
- [ ] Set a POC starting recommendation of 30 days Analytics log retention with the workspace owner, preserving longer required retention and existing shared-table policies. Read back table retention and access rather than changing the whole workspace for this POC.
- [ ] Create a resource-group `Monthly` budget using the approved amount/currency, with actual-spend alerts at 80% and 100% and a forecast alert at 100%. Set workload/platform cost-owner recipients and explicit start/end dates. Budgets notify; they do not stop resources or impose a spending cap.
- [ ] Reuse or configure the central subscription Activity Log export for `Administrative`, `Security`, `Policy`, `ServiceHealth` and `ResourceHealth`; keep it in platform state and avoid a duplicate assignment.
- [ ] Configure separate GitLab HTTP state names for network and AI workload roots using the [exact backend URL/lock settings](README.md#state-and-deployment). Use `POST` to lock, `DELETE` to unlock, a 5-second starting retry interval, and protected jobs serialized by state name. Pass resource IDs between roots; keep credentials out of HCL and tfvars.
- [ ] Run the reviewed pipeline plan and authorized deployment for each owning root in dependency order; stop unexpected deletes, replacements or changes to shared resources.
- [ ] Apply and verify `Owner`, `CostCenter`, `Environment`, `DataClassification` and `DeployedByRepo` on taggable workload resources. Resolve the [Search tag limitation](README.md#tag-coverage) through the approved existing tag policy or supported owning Search configuration: Foundry AVM `0.11.3` tags its private endpoint but omits tags on the Search service. The supplied resource-group tag policies do not inherit or remediate these tags.
- [ ] Test private endpoint access, builder/consumer permissions and an allowed/denied policy operation. Produce one approved audit event per service and confirm it reaches the expected table; test Blob recovery and a separate-destination Cosmos restore without deleting live data. Record resource IDs and actual results; a mock plan or configured setting is not evidence that the test passed.

## Scope and handoff

This builds the Azure resources, not application agents, prompts, ingestion,
Jira/SharePoint integration or Teams publication. POC sizing is not a production
availability commitment. Add Key Vault/CMK, gateways or production redundancy only
where required by the approved design. Use the existing network routine when it
already owns the spoke, NSGs and routing; do not deploy a second copy.

Review owner: ____________________  Date: __________  Open items: ______________

## References

- https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/
- https://learn.microsoft.com/azure/architecture/ai-ml/architecture/baseline-microsoft-foundry-landing-zone
- https://learn.microsoft.com/en-us/azure/governance/management-groups/manage
- https://learn.microsoft.com/en-us/azure/governance/policy/concepts/effect-basics
- https://learn.microsoft.com/en-us/azure/reliability/regions-list
- https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/limits-quotas-regions
- https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability
- https://learn.microsoft.com/en-us/azure/search/search-region-support
- https://learn.microsoft.com/en-us/azure/search/search-sku-tier
- https://learn.microsoft.com/en-us/azure/storage/common/storage-redundancy
- https://learn.microsoft.com/en-us/azure/cosmos-db/tutorial-global-distribution
- https://learn.microsoft.com/en-us/azure/cosmos-db/continuous-backup-restore-introduction
- https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks
- https://learn.microsoft.com/en-us/azure/container-apps/firewall-integration
- https://learn.microsoft.com/en-us/azure/cosmos-db/how-to-configure-private-endpoints
- https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns-integration
- https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry
- https://learn.microsoft.com/en-us/azure/azure-monitor/logs/data-retention-configure
- https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-acm-create-budgets
- https://docs.gitlab.com/user/infrastructure/iac/terraform_state/