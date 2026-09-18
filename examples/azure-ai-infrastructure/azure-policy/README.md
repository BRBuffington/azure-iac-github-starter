# Azure AI POC policy JSON

A scoped composition of Microsoft built-ins aligned with the CAF landing-zone
and private AI infrastructure guidance. This is a starter recommendation, not a
Microsoft-published initiative, the complete ALZ policy library or a compliance
certification. No policy has been assigned or enforced by these examples.

## Files and adoption

| File | Purpose |
| --- | --- |
| [initiative.json](initiative.json) | Custom initiative containing 16 references to 12 existing Microsoft built-ins; no copied or custom policy rules |
| [assignment.example.json](assignment.example.json) | Management-group assignment skeleton with `DoNotEnforce` and explicit scope placeholders |
| [parameters.example.json](parameters.example.json) | Parameter values for that assignment: customer-selected regions, five tag names and four effect groups |

These are resource/parameter JSON inputs, not ARM deployment templates or a new
Terraform root. Adopt them into the platform owner's existing governance
Terraform configuration and approved plan/apply pipeline. The two workload roots
in this example do not load or deploy these files automatically.

1. Review inherited assignments first. Reuse an existing equivalent control
   instead of assigning it twice; preserve inherited enforcement. The initiative
   definition must live at the assignment management group or an ancestor. Its
   assignment affects all matching resources below that scope, not just the
   resources created by the AI example.
2. Replace both management-group placeholders and choose the regions using
   [deployment checklist step 0](../deployment-checklist.md#0-choose-the-deployment-region).
   Replace `<deployment-region>` with actual Azure location names, not naming
   aliases. No region is preselected. Match the five tag names to the adopting
   Terraform configuration; tag values belong on the resources, not in this file.
3. Supply `initiative.json.properties.parameters` and `policyDefinitions` to the
   existing policy-set resource. For the assignment, set `properties.parameters`
   to the entire object from `parameters.example.json`, and bind
   `policyDefinitionId` to the created or reused initiative's actual resource ID.
   The assignment skeleton intentionally leaves `parameters` empty: JSON does
   not include another file automatically, and it is incomplete until composed.
4. Keep `enforcementMode` as `DoNotEnforce` for the first approved assignment.
   Review compliance results and inherited-policy interactions. Confirm private
   connectivity, managed-identity roles and required portal/SDK workflows before
   blocking key-based or public access.
5. After the platform owner approves the results, change the assignment to
   `Default` through the reviewed pipeline and test allowed and denied operations.
   The `Deny` settings then block noncompliant creates/updates; they do not repair
   existing resources. Correct those resources in their owning Terraform stack.

`DoNotEnforce` evaluates compliance without enforcing this assignment's effects.
It is not the same as an `Audit` effect or a `Disabled` policy. The four effect
parameters accept `Audit`, `Deny` or `Disabled`. The five tag references have a
fixed `Deny` effect and no effect parameter: changing the other effects to
`Audit` does not make the tags audit-only once assignment enforcement is enabled.

No assignment identity, role grant or remediation task is needed for these
Audit/Deny controls. There are no Modify, Append or DeployIfNotExists policies;
private endpoints, DNS zone groups and diagnostics remain with their existing
Terraform/platform owner.

## Included controls

Every ID below is under `/providers/Microsoft.Authorization/policyDefinitions/`.
Links point to the Microsoft rule source. Versions were checked on 2026-09-18;
references do not specify `definitionVersion`, so this is not a frozen copy.
Recheck the definitions and version selection in the adopting environment.

| Control | Built-in ID | Reviewed version |
| --- | --- | --- |
| [Allowed resource locations](https://raw.githubusercontent.com/Azure/azure-policy/master/built-in-policies/policyDefinitions/General/AllowedLocations_Deny.json) | `e56962a6-4747-49cd-b67b-bf8b01975c4c` | 1.1.0 |
| [Allowed resource-group locations](https://raw.githubusercontent.com/Azure/azure-policy/master/built-in-policies/policyDefinitions/General/ResourceGroupAllowedLocations_Deny.json) | `e765b5de-1225-4ba3-bd56-1ac6695af988` | 1.1.0 |
| [Required resource-group tag](https://raw.githubusercontent.com/Azure/azure-policy/master/built-in-policies/policyDefinitions/Tags/ResourceGroupRequireTag_Deny.json), five references: Owner, CostCenter, Environment, DataClassification, DeployedByRepo | `96670d01-0a4d-4649-9c89-2d3abc0a5025` | 1.0.0 |
| [Foundry and Search local authentication disabled](https://raw.githubusercontent.com/Azure/azure-policy/master/built-in-policies/policyDefinitions/Azure%20Ai%20Services/DisableLocalAuth_Audit.json) | `71ef260a-8f18-47b7-abcb-62d0673d94dc` | 1.1.0 |
| [AI Services network access restricted](https://raw.githubusercontent.com/Azure/azure-policy/master/built-in-policies/policyDefinitions/Azure%20Ai%20Services/NetworkAcls_Audit.json) | `037eea7a-bd0a-46c5-9a66-03aea78705d3` | 3.3.0 |
| [Search public network access disabled](https://raw.githubusercontent.com/Azure/azure-policy/master/built-in-policies/policyDefinitions/Search/RequirePublicNetworkAccessDisabled_Deny.json) | `ee980b6d-0eca-4501-8d54-f6290fd512c3` | 1.0.1 |
| [Storage public network access restricted](https://raw.githubusercontent.com/Azure/azure-policy/master/built-in-policies/policyDefinitions/Storage/StoragePublicNetworkAccess_AuditDeny.json) | `b2982f36-99f2-4db5-8eff-283140c09693` | 1.1.0 |
| [Cosmos DB public network access disabled](https://raw.githubusercontent.com/Azure/azure-policy/master/built-in-policies/policyDefinitions/Cosmos%20DB/Cosmos_PrivateNetworkAccess_AuditDeny.json) | `797b37f7-06b8-444c-b1ad-fc62867f335a` | 1.0.0 |
| [Storage shared-key access disabled](https://raw.githubusercontent.com/Azure/azure-policy/master/built-in-policies/policyDefinitions/Storage/StorageAccountAllowSharedKeyAccess_Audit.json) | `8c6a50c6-9ffd-4ae7-986f-5fa6111f9a54` | 2.0.0 |
| [Cosmos DB local authentication disabled](https://raw.githubusercontent.com/Azure/azure-policy/master/built-in-policies/policyDefinitions/Cosmos%20DB/Cosmos_DisableLocalAuth_AuditDeny.json) | `5450f5bd-9c72-4390-a9c4-a7aba4edfdd2` | 1.2.0 |
| [Storage secure transfer required](https://raw.githubusercontent.com/Azure/azure-policy/master/built-in-policies/policyDefinitions/Storage/Storage_AuditForHTTPSEnabled_Audit.json) | `404c3081-a854-4457-ae30-26a93ef643f9` | 2.0.0 |
| [Storage TLS setting `TLS1_2`](https://raw.githubusercontent.com/Azure/azure-policy/master/built-in-policies/policyDefinitions/Storage/StorageAccountMinimumTLSVersion_Audit.json) | `fe83a0eb-a853-422d-aac2-1bffd182c5d0` | 1.0.0 |

## Coverage limits

- **Private-only access:** the active AI network built-in permits Cognitive
  Services accounts with public access disabled OR `networkAcls.defaultAction`
  set to `Deny`. Selected public networks can therefore be compliant. It also
  evaluates Search, where the separate Search policy requires public access
  disabled. The older Cognitive Services public-access policy
  `0725b4dd-7e76-479c-a735-68e7ee23d5ca` is deprecated and is not included.
- **Storage networking:** the built-in accepts either `Disabled` or
  `SecuredByPerimeter`. The companion Terraform deliberately uses the stricter
  `Disabled` setting for both Foundry and Storage. A green initiative result alone
  does not prove private-only access, endpoint existence, DNS or connectivity.
- **Tags:** these checks require tag presence on resource groups only. They do
  not validate values, reject empty values, inherit tags or tag child resources.
  Continue applying the common tags in Terraform.
- **Regions:** the two location policies check resource and resource-group
  locations, not model/tool availability, quota, Cosmos replication locations or
  model inference/data-processing residency. The resource policy exempts global
  resources and has the built-in's Indexed-mode limits.
- **Authentication:** the AI policy covers Cognitive Services accounts and
  Search, not application authorization or RBAC grants. The Cosmos policy
  excludes MongoDB, Cassandra and Gremlin capabilities; this example uses NoSQL.
- **Broader governance:** inherited landing-zone controls still apply. This
  package does not add CMK, production HA/DR, automatic diagnostics, content
  filters or application-agent policies, and does not replace the starter's
  separate OPA Terraform-plan checks.

## Guidance

- [CAF Azure landing zones](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/)
- [Baseline Microsoft Foundry landing zone](https://learn.microsoft.com/azure/architecture/ai-ml/architecture/baseline-microsoft-foundry-landing-zone)
- [Microsoft ALZ policy library](https://github.com/Azure/Azure-Landing-Zones-Library/tree/main/platform/alz/policy_set_definitions)
- [Azure Policy initiative structure](https://learn.microsoft.com/en-us/azure/governance/policy/concepts/initiative-definition-structure)
- [Assignment parameters and enforcement mode](https://learn.microsoft.com/en-us/azure/governance/policy/concepts/assignment-structure)