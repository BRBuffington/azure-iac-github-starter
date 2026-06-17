# Grounding a Foundry IQ agent on this repository

This repo's guidance (the `docs/`, `README.md`, and policy files) can become a
**knowledge source** that an AI agent retrieves from, so the team can ask an agent
"how do we handle Terraform state here?" or "what does the OPA gate enforce?" and get
cited answers drawn from this repo.

Microsoft's managed knowledge layer for this is **Foundry IQ**: you create a
**knowledge base** (one or more **knowledge sources** + retrieval parameters) on an
Azure AI Search service, then connect it to an agent in Foundry Agent Service. The
agent queries the knowledge base over the Model Context Protocol (MCP) and gets
permission-aware, citation-backed answers.

> There is **no GitHub knowledge-source connector**. You bridge the repo onto a
> supported source. The recommended bridge for this repo is an **Azure Blob**
> knowledge source: sync the repo's content to a blob container, and Foundry IQ
> auto-generates the indexer pipeline (chunking, vector embeddings, scheduled
> incremental refresh) and queries it locally on your search service.

## The path (repo → blob → knowledge source → knowledge base → agent)

1. **Sync repo content to a blob container** in your tenant. This repo ships
   `.github/workflows/foundry-iq-sync.yml` to do this on every push to `main` (it
   stages `README.md`, `docs/`, and the policy files, then runs `az storage blob
   sync`). It is **inert until you set the `FOUNDRY_IQ_*` repo variables**.
2. **Create an Azure Blob knowledge source** pointing at that container. Foundry IQ
   generates a data source + skillset + chunked, vectorized index for you — no
   hand-built index.
3. **Create a knowledge base** that references the knowledge source.
4. **Connect the knowledge base to your agent** (a `RemoteTool` project connection +
   the `knowledge_base_retrieve` MCP tool). For a Terraform-authoring agent, this is
   how it learns *your* conventions instead of generic ones.

Steps 2–4 are done once in the Microsoft Foundry portal (Build → Knowledge, then
Agents) or programmatically; step 1 is the only recurring, repo-side automation.

## API versions (current as of 2026-06)

- **`2026-04-01`** — generally available agentic retrieval (knowledge bases,
  knowledge sources, minimal extractive retrieval).
- **`2026-05-01-preview`** — preview features: LLM query planning, answer synthesis,
  configurable reasoning effort, and the preview knowledge sources. The knowledge
  base **MCP endpoint** uses this version:
  `https://<search>.search.windows.net/knowledgebases/<kb-name>/mcp?api-version=2026-05-01-preview`
- The Foundry **project connection** (RemoteTool) is created via Azure Resource
  Manager `2025-10-01-preview`.

## RBAC (keyless, recommended)

- Creating the knowledge base/source: **Search Service Contributor** on the search
  service (plus **Search Index Data Contributor** to load the generated index).
- The Foundry **project's managed identity** needs **Search Index Data Reader** on
  the search service to query the knowledge base.
- If the knowledge base uses an LLM (for planning/synthesis), the **search service's
  managed identity** needs **Cognitive Services User** on the Microsoft Foundry
  resource.
- The sync workflow's OIDC identity needs **Storage Blob Data Contributor** on the
  target container.

## Regulated-tenant posture (matches this repo's recommendations)

- **Use an indexed source (blob), not a remote one.** Indexed content is ingested
  into *your* AI Search service and stays in your tenant. Microsoft's docs warn that
  **remote** knowledge sources (Web/Bing, remote SharePoint, MCP server) can cause
  data to flow **outside the Azure compliance boundary** — avoid them on the
  regulated path.
- Keep the storage account, AI Search service, and the agent **private-endpoint
  only**. That means the sync job must run on a **self-hosted, in-network runner**
  (see `runners/README.md`) — the same reason the Terraform pipeline does. Set
  `RUNNER_LABELS` accordingly.
- Foundry IQ honors **Microsoft Purview sensitivity labels** and **enforces
  permissions at query time**, and can run queries under the caller's Entra
  identity — so agents return only content the caller is authorized to see.
- This repo is a *reference* with no sensitive data, so labeling isn't required here;
  apply it when you point a knowledge source at real regulated content.

## Citations

Blob knowledge sources return the **original document URL** in citations, so an agent
grounded on this repo cites the specific doc/policy file it used. (Search-index
sources instead fall back to the knowledge base's MCP endpoint.)

## Alternatives (when blob isn't the right fit)

- **File knowledge source (preview)** — upload the docs directly to AI Search, no
  blob/indexer to manage. Fastest one-time start; weaker for continuous sync.
- **Bring-your-own search index** — build the index yourself and wrap it, when you
  need full control of chunking/skillset.
- **MCP server knowledge source (remote, preview)** — expose the repo via a GitHub
  MCP server for *live* retrieval, no index. Always current, but it's a remote source
  (compliance-boundary caveat above) and has no semantic chunking.

## References (Microsoft Learn)

- https://learn.microsoft.com/azure/foundry/agents/concepts/what-is-foundry-iq
- https://learn.microsoft.com/azure/foundry/agents/how-to/foundry-iq-connect
- https://learn.microsoft.com/azure/search/agentic-knowledge-source-overview
- https://learn.microsoft.com/azure/search/agentic-retrieval-how-to-create-knowledge-base
- https://learn.microsoft.com/azure/search/agentic-retrieval-overview
